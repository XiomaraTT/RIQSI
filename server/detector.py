import asyncio
import json
import cv2
import websockets
import time
import numpy as np
from abc import ABC, abstractmethod

PORT = 8765

class TranslationService:
    def __init__(self):
        self.translations = {
            # Clases Peatonales / Vía Pública
            "pole": "poste", "reflective_cone": "cono", "spherical_roadblock": "bolardo",
            "warning_column": "columna", "fire_hydrant": "hidrante", "ashcan": "tacho de basura",
            "person": "persona", "bicycle": "bicicleta", "car": "auto", "bus": "autobús",
            "truck": "camión", "motorcycle": "motocicleta", "stop_sign": "señal de pare",
            "dog": "perro", "traffic light": "semáforo", "door": "puerta", "wall": "pared",
            # Clases de Interiores (COCO Dataset estándar para que nunca falle con muebles)
            "chair": "silla", "couch": "sillón", "bed": "cama", "dining table": "mesa",
            "tv": "pantalla", "laptop": "computadora", "bottle": "botella", "cup": "taza",
            "door": "puerta", "refrigerator": "refrigerador", "potted plant": "planta",
            "stairs": "escaleras", "backpack": "mochila"
        }

    def translate(self, label: str) -> str:
        clean = label.lower().strip()
        if clean.isdigit() or clean.startswith("0000"):
            return "obstáculo"
        return self.translations.get(clean, clean)


class YoloDetector:
    def __init__(self, model_path="best.onnx"):
        from ultralytics import YOLO
        import os
        
        # Si el modelo personalizado no existe o falla, usa yolov8n que tiene 80 clases universales
        if not os.path.exists(model_path):
            model_path = "best.pt" if os.path.exists("best.pt") else "yolov8n.pt"
            
        print(f"[INFO] Cargando modelo: {model_path}")
        self.model = YOLO(model_path, task="detect")

    def detect(self, frame) -> list:
        # imgsz=320 y conf=0.45 para balance perfecto entre velocidad y alta sensibilidad
        results = self.model.predict(source=frame, verbose=False, conf=0.45, imgsz=320)
        detections = []
        for r in results:
            for box in r.boxes:
                cls_id = int(box.cls[0])
                label = self.model.names[cls_id]
                xyxy = box.xyxy[0].tolist()
                conf = float(box.conf[0])
                detections.append({
                    "label": label,
                    "confidence": conf,
                    "box": [int(v) for v in xyxy]
                })
        return detections


class FallbackDetector:
    """Detecta paredes o bloqueos frontales a corta distancia cuando la cámara está cubierta."""
    def detect_wall(self, frame) -> list:
        h, w, _ = frame.shape
        # Reducir a tamaño microscópico para evaluación en 0.5 ms
        small = cv2.resize(frame, (80, 60))
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        
        # Si no hay variación ni textura en el centro, hay una superficie opaca a menos de 50cm
        center = gray[15:45, 20:60]
        variance = cv2.Laplacian(center, cv2.CV_64F).var()
        
        if variance < 22.0:
            return [{
                "label": "pared",
                "confidence": 0.90,
                "box": [int(w * 0.1), int(h * 0.1), int(w * 0.9), int(h * 0.9)]
            }]
        return []


class SpatialAnalyser:
    def __init__(self, translator: TranslationService):
        self.translator = translator

    def analyse(self, label: str, box: list, frame_w: int, frame_h: int) -> dict:
        x1, y1, x2, y2 = box
        w_box = x2 - x1
        h_box = y2 - y1
        area_ratio = (w_box * h_box) / float(frame_w * frame_h)
        bottom_y_ratio = y2 / float(frame_h)
        x_center = ((x1 + x2) / 2.0) / float(frame_w)

        # Posición horizontal
        if x_center < 0.35:
            pos = "Izquierda"
        elif x_center > 0.65:
            pos = "Derecha"
        else:
            pos = "Adelante"

        trans_label = self.translator.translate(label).capitalize()
        pos_desc = "adelante" if pos == "Adelante" else f"a la {pos.lower()}"
        is_wall = label.lower() == "pared"

        # LÓGICA DE DISTANCIA POR PERSPECTIVA FÍSICA:
        # 1. MUY CERCA: La base toca el suelo inmediato (>0.85) con tamaño visible, o pared frontal
        if is_wall or (bottom_y_ratio > 0.85 and area_ratio > 0.18) or area_ratio > 0.55:
            risk = "Alto"
            distancia = "muy_cerca"
            desc = f"¡Cuidado! {trans_label} muy cerca {pos_desc}."
        # 2. CERCA: En trayectoria media
        elif bottom_y_ratio > 0.60 or area_ratio > 0.10:
            risk = "Medio"
            distancia = "cerca"
            desc = f"{trans_label} cerca {pos_desc}."
        # 3. LEJOS: Al fondo
        else:
            risk = "Bajo"
            distancia = "lejos"
            desc = f"{trans_label} {pos_desc}."

        return {
            "label": trans_label,
            "pos": pos,
            "risk": risk,
            "distancia": distancia,
            "proximity_ratio": round(area_ratio, 3),
            "desc": desc,
            "box": box
        }


class SpeechDebouncer:
    """Regula el TTS para no saturar auditivamente al usuario."""
    def __init__(self):
        self.last_text = ""
        self.last_time = 0.0

    def should_announce(self, text: str, risk: str) -> bool:
        now = time.time()
        elapsed = now - self.last_time

        if risk == "Alto":
            # Si el peligro es crítico, permite alertar tras 2.2 segundos
            if elapsed > 2.2 or text != self.last_text:
                self.last_text = text
                self.last_time = now
                return True
            return False

        # Si es riesgo medio o bajo, retiene mínimo 5.0 segundos la misma frase
        if elapsed > 5.0 and text != self.last_text:
            self.last_text = text
            self.last_time = now
            return True
        elif elapsed > 8.0:
            self.last_text = text
            self.last_time = now
            return True

        return False


class VisionServer:
    def __init__(self):
        self.detector = YoloDetector()
        self.fallback = FallbackDetector()
        self.translator = TranslationService()
        self.analyser = SpatialAnalyser(self.translator)
        self.debouncer = SpeechDebouncer()
        self.is_processing = False

    async def process_frame(self, raw_bytes, websocket):
        if self.is_processing:
            return
        self.is_processing = True

        try:
            nparr = np.frombuffer(raw_bytes, np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if frame is None:
                return

            h, w, _ = frame.shape
            
            # 1. Detección semántica
            detections = self.detector.detect(frame)
            
            # 2. Respaldo de pared solo si YOLO no detecta nada
            if not detections:
                detections = self.fallback.detect_wall(frame)

            analysed = [self.analyser.analyse(d["label"], d["box"], w, h) for d in detections]

            # Renderizado PC
            for obj in analysed:
                color = (0, 0, 255) if obj["risk"] == "Alto" else ((0, 165, 255) if obj["risk"] == "Medio" else (0, 255, 0))
                cv2.rectangle(frame, (obj["box"][0], obj["box"][1]), (obj["box"][2], obj["box"][3]), color, 2)
                cv2.putText(frame, f"{obj['label']} - {obj['distancia']}", (obj["box"][0], max(20, obj["box"][1] - 8)),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)

            cv2.imshow("Riqsi Monitor", frame)
            cv2.waitKey(1)

            if analysed:
                # Priorizar el de mayor riesgo
                analysed.sort(key=lambda x: (3 if x["risk"]=="Alto" else (2 if x["risk"]=="Medio" else 1), x["proximity_ratio"]), reverse=True)
                top = analysed[0]
                
                allow_voice = self.debouncer.should_announce(top["desc"], top["risk"])
                
                payload = {
                    "type": "detection",
                    "label": top["label"],
                    "position": top["pos"],
                    "risk": top["risk"],
                    "distancia": top["distancia"],
                    "description": top["desc"],
                    "announce_voice": allow_voice,
                    "objects": analysed[:3]
                }
                if allow_voice:
                    print(f"[VOZ ACTIVA] {top['desc']}")

                await websocket.send(json.dumps(payload))
            else:
                await websocket.send(json.dumps({"type": "clear"}))

        except Exception as e:
            print(f"[ERROR] {e}")
        finally:
            self.is_processing = False

    async def handler(self, websocket):
        print(f"[CONECTADO] {websocket.remote_address}")
        try:
            async for msg in websocket:
                if isinstance(msg, bytes):
                    await self.process_frame(msg, websocket)
        except Exception:
            pass
        finally:
            print("[DESCONECTADO]")


async def main():
    server = VisionServer()
    print(f"\n==========================================")
    print(f"   RIQSI CORE EN EJECUCIÓN (PORT: {PORT})")
    print(f"==========================================\n")
    async with websockets.serve(server.handler, "0.0.0.0", PORT):
        while True:
            await asyncio.sleep(3600)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass