"""Servidor de visión RIQSI: recibe fotos JPEG por WebSocket y responde JSON con detecciones.

Uso:  python server/detector.py [--monitor] [--port 8765]
Variables de entorno: RIQSI_TOKEN (opcional, exige ?token=...), RIQSI_MONITOR=1.
"""
import argparse
import asyncio
import hmac
import json
import os
import queue
import sys
import threading
import time
import traceback
from http import HTTPStatus
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import cv2
import numpy as np
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

sys.path.insert(0, str(Path(__file__).resolve().parent))
import riqsi_logic as logic  # noqa: E402

PORT = 8765
MAX_MESSAGE_BYTES = 2 * 1024 * 1024
ROOT = Path(__file__).resolve().parents[1]


class GroundHazardDetector:
    """Detecta huecos, zanjas o baches profundos en el pavimento descartando objetos conocidos."""
    def detect(self, frame, existing_detections=None) -> list:
        h, w, _ = frame.shape
        roi_y1 = int(h * 0.60)  # Franja inferior directa del piso
        roi = frame[roi_y1:h, :]
        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (9, 9), 0)

        roi_mean = np.mean(gray)

        # Cavidades o huecos en la acera presentan contrastes oscuros marcados
        thresh = cv2.adaptiveThreshold(blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 31, 10)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
        cleaned = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, kernel)
        contours, _ = cv2.findContours(cleaned, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        hazards = []
        min_area = (w * (h - roi_y1)) * 0.04
        max_area = (w * (h - roi_y1)) * 0.50

        for c in contours:
            area = cv2.contourArea(c)
            if min_area < area < max_area:
                x, y, bw, bh = cv2.boundingRect(c)
                aspect_ratio = bw / float(bh)
                if 0.5 < aspect_ratio < 2.8:
                    candidate_box = [x, y + roi_y1, x + bw, y + roi_y1 + bh]

                    # 1. Descartar si coincide con un objeto real detectado por YOLO
                    if existing_detections:
                        overlapped = False
                        for d in existing_detections:
                            obox = d["box"]
                            xA = max(candidate_box[0], obox[0])
                            yA = max(candidate_box[1], obox[1])
                            xB = min(candidate_box[2], obox[2])
                            yB = min(candidate_box[3], obox[3])
                            interArea = max(0, xB - xA) * max(0, yB - yA)
                            cArea = bw * bh
                            if cArea > 0 and (interArea / float(cArea)) > 0.18:
                                overlapped = True
                                break
                        if overlapped:
                            continue

                    # 2. Verificar que la zona sea verdaderamente una fosa oscura respecto al piso
                    patch = gray[y:y + bh, x:x + bw]
                    darkness = float(roi_mean) - float(np.mean(patch))
                    if darkness > 32:
                        hazards.append({
                            "label": "hueco",
                            # Confianza proporcional a qué tan oscuro es respecto al piso
                            "confidence": round(min(0.95, 0.5 + darkness / 200.0), 3),
                            "box": candidate_box
                        })
        return hazards


class YoloDetector:
    """Detector híbrido: COCO 80 clases universales + modelo especializado de vía pública."""
    def __init__(self):
        try:
            from ultralytics import YOLO
        except ImportError:
            print("[ERROR] Falta 'ultralytics'. Instala dependencias: pip install -r server/requirements.txt",
                  flush=True)
            raise SystemExit(1)

        self.models = []
        # 1. Modelo COCO Universal (80 clases: semáforos, personas, autos, bolsos, etc.)
        coco = ROOT / "yolov8n.pt"
        if coco.exists():
            print(f"[INFO] Cargando modelo universal COCO (80 clases): {coco}", flush=True)
            self.models.append((YOLO(str(coco), task="detect"), "coco"))

        # 2. Modelo de obstáculos peatonales especializados (postes, bolardos, conos)
        for name in ("best.pt", "best.onnx"):
            custom = ROOT / name
            if custom.exists():
                print(f"[INFO] Cargando modelo especializado: {custom}", flush=True)
                self.models.append((YOLO(str(custom), task="detect"), "custom"))
                break

        if not self.models:
            print(f"[ADVERTENCIA] No se encontró ningún modelo (yolov8n.pt, best.pt, best.onnx) en {ROOT}. "
                  "Solo funcionarán las heurísticas de pared y hueco.", flush=True)

    def detect(self, frame) -> list:
        detections = []
        for model, m_type in self.models:
            # conf=0.35 para captar semáforos, bolsos y objetos cotidianos con alta sensibilidad
            results = model.predict(source=frame, verbose=False, conf=0.35, imgsz=320)
            for r in results:
                for box in r.boxes:
                    cls_id = int(box.cls[0])
                    label = model.names[cls_id]

                    # Ignorar códigos numéricos internos del modelo especializado
                    if m_type == "custom" and (label.isdigit() or label.startswith("0000")):
                        continue

                    xyxy = box.xyxy[0].tolist()
                    detections.append({
                        "label": label,
                        "confidence": float(box.conf[0]),
                        "box": [int(v) for v in xyxy]
                    })
        # Un mismo objeto puede salir en ambos modelos: NMS por clase normalizada
        return logic.nms_merge(detections, 0.5)


class FallbackDetector:
    """Detecta paredes o bloqueos frontales a corta distancia cuando la cámara está cubierta."""
    def detect_wall(self, frame) -> list:
        h, w, _ = frame.shape
        small = cv2.resize(frame, (80, 60))
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        center = gray[15:45, 20:60]
        variance = cv2.Laplacian(center, cv2.CV_64F).var()

        if variance < 22.0:
            return [{
                "label": "pared",
                # Menor varianza (superficie más uniforme) => mayor confianza
                "confidence": round(min(0.95, 0.5 + (22.0 - variance) / 44.0), 3),
                "box": [int(w * 0.1), int(h * 0.1), int(w * 0.9), int(h * 0.9)]
            }]
        return []


class ConnectionState:
    """Estado independiente por conexión (seguimiento, debouncer, confirmación de heurísticas)."""
    def __init__(self):
        self.tracker = logic.SpatialTracker()
        self.debouncer = logic.SpeechDebouncer()
        self.confirmer = logic.HazardConfirmer(3)


class Monitor:
    """Ventana opcional de depuración en su propio hilo (no bloquea el event loop)."""
    def __init__(self):
        self.q = queue.Queue(maxsize=1)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def show(self, frame):
        try:
            self.q.get_nowait()
        except queue.Empty:
            pass
        try:
            self.q.put_nowait(frame)
        except queue.Full:
            pass

    def _run(self):
        try:
            while not self.stop.is_set():
                try:
                    frame = self.q.get(timeout=0.2)
                except queue.Empty:
                    cv2.waitKey(1)
                    continue
                cv2.imshow("Riqsi Monitor", frame)
                cv2.waitKey(1)
        except Exception:
            traceback.print_exc()
        finally:
            cv2.destroyAllWindows()

    def close(self):
        self.stop.set()
        self.thread.join(timeout=2)


def draw_monitor(frame, analysed, scene_desc, scene_risk):
    h, w, _ = frame.shape
    for obj in analysed:
        color = (0, 0, 255) if obj["risk"] == "Alto" else ((0, 165, 255) if obj["risk"] == "Medio" else (0, 255, 0))
        cv2.rectangle(frame, (obj["box"][0], obj["box"][1]), (obj["box"][2], obj["box"][3]), color, 2)
        cv2.putText(frame, f"{obj['label']}", (obj["box"][0], max(22, obj["box"][1] - 8)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)
    banner_color = (0, 0, 180) if scene_risk == "Alto" else ((0, 120, 200) if scene_risk == "Medio" else (35, 120, 35))
    cv2.rectangle(frame, (0, h - 45), (w, h), (15, 15, 15), -1)
    cv2.rectangle(frame, (0, h - 45), (8, h), banner_color, -1)
    cv2.putText(frame, f"ENTORNO: {scene_desc}", (16, h - 16),
                cv2.FONT_HERSHEY_SIMPLEX, 0.50, (255, 255, 255), 2)


class VisionServer:
    def __init__(self, token=None, monitor=None):
        self.detector = YoloDetector()
        self.ground_detector = GroundHazardDetector()
        self.fallback = FallbackDetector()
        self.token = token
        self.monitor = monitor
        self.active = None  # único cliente activo
        self._infer_lock = threading.Lock()

    def infer(self, raw_bytes: bytes, state: ConnectionState):
        """Trabajo pesado y síncrono (se ejecuta en un hilo). Devuelve el payload o None."""
        nparr = np.frombuffer(raw_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if frame is None:
            return None
        h, w, _ = frame.shape

        with self._infer_lock:
            detections = self.detector.detect(frame)
            heuristics = self.ground_detector.detect(frame, existing_detections=detections)
            if not detections:
                heuristics += self.fallback.detect_wall(frame)
        # Las heurísticas deben repetirse en varios frames seguidos antes de reportarse
        detections.extend(state.confirmer.confirm(heuristics, w))

        analysed = state.tracker.analyse_frame(detections, w, h)
        scene_desc, scene_risk, _advice = logic.synthesize(analysed)

        if self.monitor:
            draw_monitor(frame, analysed, scene_desc, scene_risk)
            self.monitor.show(frame)

        if not analysed:
            return logic.build_payload([], scene_desc, scene_risk, False, w, h)
        allow_voice = state.debouncer.should_announce(analysed, scene_risk, time.monotonic())
        if allow_voice:
            print(f"[VOZ ENTORNO] {scene_desc}", flush=True)
        return logic.build_payload(analysed, scene_desc, scene_risk, allow_voice, w, h)

    async def process_request(self, connection, request):
        if not self.token:
            return None
        qs = parse_qs(urlsplit(request.path).query)
        given = (qs.get("token") or [""])[0]
        if not hmac.compare_digest(given.encode(), self.token.encode()):
            return connection.respond(HTTPStatus.UNAUTHORIZED, "Token inválido\n")
        return None

    async def handler(self, websocket):
        # Solo un cliente activo: el nuevo reemplaza al anterior
        previous = self.active
        self.active = websocket
        if previous is not None:
            try:
                await previous.close(code=1008, reason="Reemplazado por otra conexión")
            except Exception:
                pass

        print(f"[CONECTADO DESDE CELULAR] {websocket.remote_address}", flush=True)
        state = ConnectionState()
        latest = {"frame": None}
        has_frame = asyncio.Event()

        async def reader():
            # Guarda solo el último frame; los viejos se descartan
            async for msg in websocket:
                if isinstance(msg, bytes):
                    latest["frame"] = msg
                    has_frame.set()

        async def processor():
            while True:
                await has_frame.wait()
                has_frame.clear()
                raw, latest["frame"] = latest["frame"], None
                if raw is None:
                    continue
                try:
                    payload = await asyncio.to_thread(self.infer, raw, state)
                except Exception:
                    print("[ERROR FRAME]", flush=True)
                    traceback.print_exc()
                    continue
                if payload is not None:
                    await websocket.send(json.dumps(payload))

        tasks = [asyncio.create_task(reader()), asyncio.create_task(processor())]
        try:
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for t in done:
                t.result()
        except ConnectionClosed:
            pass
        except Exception:
            print("[ERROR CONEXION]", flush=True)
            traceback.print_exc()
        finally:
            for t in tasks:
                t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            if self.active is websocket:
                self.active = None
            print("[DESCONECTADO]", flush=True)


async def main(port: int, monitor_on: bool):
    token = os.environ.get("RIQSI_TOKEN") or None
    monitor = Monitor() if monitor_on else None
    server = VisionServer(token=token, monitor=monitor)
    print("\n=======================================================")
    print("   RIQSI CORE - SISTEMA DE VISIÓN Y GUÍA ESPACIAL")
    print(f"   Puerto: {port} | Modelos: YOLOv8 + Detección de Suelo")
    print(f"   Token: {'requerido (?token=)' if token else 'no requerido'} | Monitor: {'sí' if monitor else 'no'}")
    print("=======================================================\n", flush=True)
    try:
        async with serve(server.handler, "0.0.0.0", port, max_size=MAX_MESSAGE_BYTES,
                         process_request=server.process_request) as ws_server:
            await ws_server.serve_forever()
    finally:
        if monitor:
            monitor.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Servidor de visión RIQSI")
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--monitor", action="store_true", help="Muestra ventana de depuración")
    args = parser.parse_args()
    monitor_flag = args.monitor or os.environ.get("RIQSI_MONITOR") == "1"
    try:
        asyncio.run(main(args.port, monitor_flag))
    except KeyboardInterrupt:
        pass
