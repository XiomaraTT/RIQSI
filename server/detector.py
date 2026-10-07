import asyncio
import json
import cv2
import websockets
import time
import numpy as np
import os

PORT = 8765

class TranslationService:
    def __init__(self):
        self.translations = {
            # Vía pública / Tráfico / Señalética
            "traffic light": "semáforo", "stop sign": "señal de pare", "stop_sign": "señal de pare",
            "fire hydrant": "hidrante", "fire_hydrant": "hidrante", "parking meter": "parquímetro",
            "bench": "banca", "pole": "poste", "reflective_cone": "cono de seguridad",
            "spherical_roadblock": "bolardo", "warning_column": "columna",
            "ashcan": "tacho de basura", "crosswalk": "paso peatonal",

            # Personas y animales
            "person": "persona", "pedestrian": "peatón", "dog": "perro", "cat": "gato",
            "bird": "ave", "horse": "caballo", "sheep": "oveja", "cow": "vaca",

            # Vehículos
            "car": "auto", "bus": "autobús", "truck": "camión", "motorcycle": "motocicleta",
            "motorbike": "motocicleta", "bicycle": "bicicleta", "tricycle": "triciclo",
            "train": "tren", "airplane": "avión", "boat": "bote",

            # Accesorios y objetos personales
            "backpack": "mochila", "umbrella": "paraguas", "handbag": "bolso",
            "tie": "corbata", "suitcase": "maleta", "bottle": "botella", "cup": "taza",
            "cell phone": "teléfono", "keyboard": "teclado", "mouse": "ratón",
            "sign": "señal", "traffic sign": "señal de tránsito",

            # Peligros en el suelo, caídas y desniveles
            "hole": "hueco", "pothole": "hueco", "hueco": "hueco", "desnivel": "desnivel",
            "stairs": "escaleras", "door": "puerta", "wall": "pared",

            # Interiores y muebles
            "chair": "silla", "couch": "sillón", "bed": "cama", "dining table": "mesa",
            "tv": "pantalla", "laptop": "computadora portátil", "refrigerator": "refrigerador",
            "potted plant": "planta", "sink": "lavamanos"
        }

    def translate(self, label: str) -> str:
        clean = label.lower().strip()
        if clean.isdigit() or clean.startswith("0000"):
            return "obstáculo"
        return self.translations.get(clean, clean)


class GroundHazardDetector:
    """Detecta huecos, zanjas o baches profundos en el pavimento descartando objetos conocidos."""
    def detect(self, frame, existing_detections=None) -> list:
        h, w, _ = frame.shape
        roi_y1 = int(h * 0.60) # Franja inferior directa del piso
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

                    # 1. Descartar si coincide con un objeto real detectado por YOLO (cama, laptop, teclado, etc.)
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
                    patch = gray[y:y+bh, x:x+bw]
                    if np.mean(patch) < (roi_mean - 32):
                        hazards.append({
                            "label": "hueco",
                            "confidence": 0.85,
                            "box": candidate_box
                        })
        return hazards


class YoloDetector:
    """Detector híbrido: COCO 80 clases universales + modelo especializado de vía pública."""
    def __init__(self):
        from ultralytics import YOLO

        self.models = []
        # 1. Modelo COCO Universal (80 clases: semáforos, personas, autos, bolsos, etc.)
        if os.path.exists("yolov8n.pt"):
            print("[INFO] Cargando modelo universal COCO (80 clases): yolov8n.pt")
            self.models.append((YOLO("yolov8n.pt", task="detect"), "coco"))

        # 2. Modelo de obstáculos peatonales especializados (postes, bolardos, conos)
        if os.path.exists("best.pt"):
            print("[INFO] Cargando modelo especializado: best.pt")
            self.models.append((YOLO("best.pt", task="detect"), "custom"))
        elif os.path.exists("best.onnx"):
            print("[INFO] Cargando modelo especializado: best.onnx")
            self.models.append((YOLO("best.onnx", task="detect"), "custom"))

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
        small = cv2.resize(frame, (80, 60))
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
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

        # 1. Posición horizontal
        if x_center < 0.38:
            pos = "Izquierda"
        elif x_center > 0.62:
            pos = "Derecha"
        else:
            pos = "Adelante"

        trans_label = self.translator.translate(label).capitalize()
        pos_desc = "adelante" if pos == "Adelante" else f"a la {pos.lower()}"
        is_wall = label.lower() == "pared"
        is_hole = label.lower() in ["hueco", "desnivel", "pothole", "hole"]
        is_traffic_light = "semáforo" in trans_label.lower()

        # 2. CONSEJO DE NAVEGACIÓN Y EVASIÓN PARA PERSONAS CIEGAS
        if is_wall or area_ratio > 0.60:
            consejo = "Paso bloqueado. Detente"
        elif pos == "Adelante":
            # Si está en el centro, busca el desvío con mayor despeje
            if x_center <= 0.50:
                consejo = "Muévete al lado derecho"
            else:
                consejo = "Muévete al lado izquierdo"
        elif pos == "Izquierda":
            consejo = "Mantente a la derecha"
        else: # Derecha
            consejo = "Mantente a la izquierda"

        # 3. LÓGICA DE DISTANCIA Y RIESGO
        if is_hole:
            # Los huecos en el suelo son peligro crítico
            risk = "Alto"
            distancia = "inmediato" if bottom_y_ratio > 0.70 else "cerca"
            desc = f"Hueco adelante en el suelo. {consejo}."
        elif is_wall:
            risk = "Alto"
            distancia = "muy_cerca"
            desc = f"Pared frontal muy cerca. Detente."
        elif (bottom_y_ratio > 0.85 and area_ratio > 0.20) or area_ratio > 0.50:
            risk = "Medio"
            distancia = "muy_cerca"
            desc = f"{trans_label} muy cerca {pos_desc}. {consejo}."
        elif is_traffic_light:
            risk = "Bajo"
            distancia = "cerca" if bottom_y_ratio > 0.60 else "lejos"
            desc = f"{trans_label} {pos_desc}."
        elif bottom_y_ratio > 0.60 or area_ratio > 0.10:
            risk = "Medio"
            distancia = "cerca"
            desc = f"{trans_label} cerca {pos_desc}."
        else:
            risk = "Bajo"
            distancia = "lejos"
        box_norm = [
            round(x1 / float(frame_w), 4),
            round(y1 / float(frame_h), 4),
            round(x2 / float(frame_w), 4),
            round(y2 / float(frame_h), 4)
        ]

        return {
            "label": trans_label,
            "pos": pos,
            "position": pos,
            "risk": risk,
            "distancia": distancia,
            "proximity_ratio": round(area_ratio, 3),
            "consejo": consejo,
            "desc": desc,
            "box": box,
            "box_norm": box_norm
        }


class SceneSynthesizer:
    """Sintetiza de forma panorámica, descriptiva y natural todo lo que rodea a la persona ciega."""
    def synthesize(self, analysed_objects: list) -> tuple:
        if not analysed_objects:
            return "Camino despejado al frente.", "Bajo", "Vía libre"

        # 1. Peligro crítico prioritario (Huecos o Pared frontal)
        critical = [o for o in analysed_objects if o["risk"] == "Alto" and o["label"].lower() in ["hueco", "desnivel", "pared"]]
        if critical:
            c = critical[0]
            label = c["label"].lower()
            consejo = c.get("consejo", "detente")
            if label in ["hueco", "desnivel"]:
                desc = f"¡Cuidado! Hueco adelante en el suelo. {consejo}."
            else:
                desc = "¡Atención! Pared al frente. Detente."
            return desc, "Alto", consejo

        # 2. Agrupación por cuadrantes espaciales (Adelante, Izquierda, Derecha)
        from collections import Counter
        pos_map = {"Adelante": [], "Izquierda": [], "Derecha": []}
        for o in analysed_objects:
            p = o.get("pos", "Adelante")
            if p in pos_map:
                pos_map[p].append(o["label"].lower())

        sections = []

        # Objetos al frente
        if pos_map["Adelante"]:
            cnts = Counter(pos_map["Adelante"])
            items = []
            for k, c in cnts.items():
                if c > 1:
                    plural = k + "s" if not k.endswith("s") else k
                    items.append(f"{c} {plural}")
                else:
                    items.append(k)
            front_text = "Al frente " + (", ".join(items[:-1]) + " y " + items[-1] if len(items) > 1 else items[0])
            sections.append(front_text)

        # Objetos a la derecha
        if pos_map["Derecha"]:
            cnts = Counter(pos_map["Derecha"])
            items = []
            for k, c in cnts.items():
                if c > 1:
                    plural = k + "s" if not k.endswith("s") else k
                    items.append(f"{c} {plural}")
                else:
                    items.append(k)
            right_text = (", ".join(items[:-1]) + " y " + items[-1] if len(items) > 1 else items[0]) + " a la derecha"
            sections.append(right_text)

        # Objetos a la izquierda
        if pos_map["Izquierda"]:
            cnts = Counter(pos_map["Izquierda"])
            items = []
            for k, c in cnts.items():
                if c > 1:
                    plural = k + "s" if not k.endswith("s") else k
                    items.append(f"{c} {plural}")
                else:
                    items.append(k)
            left_text = (", ".join(items[:-1]) + " y " + items[-1] if len(items) > 1 else items[0]) + " a la izquierda"
            sections.append(left_text)

        full_desc = ". ".join(sections).capitalize() + "."

        # Consejo de desvío si hay algo en la trayectoria inmediata del frente
        front_obstacles = [o for o in analysed_objects if o.get("pos") == "Adelante" and o.get("risk") in ["Medio", "Alto"]]
        if front_obstacles:
            advice = front_obstacles[0].get("consejo", "")
            if advice:
                full_desc += f" {advice}."
        else:
            advice = "Vía despejada"

        dominant_risk = "Medio" if front_obstacles else "Bajo"
        return full_desc, dominant_risk, advice


class SpeechDebouncer:
    """Regula el TTS con pausas naturales para que no hable de manera frenética."""
    def __init__(self):
        self.last_text = ""
        self.last_time = 0.0

    def should_announce(self, text: str, risk: str) -> bool:
        now = time.time()
        elapsed = now - self.last_time

        # Peligro crítico (hueco o pared): respuesta inmediata
        if risk == "Alto":
            if elapsed > 2.0 or text != self.last_text:
                self.last_text = text
                self.last_time = now
                return True
            return False

        # Descripciones del entorno normales: cadencia calmada de 3.8 a 4.5 segundos
        if elapsed > 3.8 and text != self.last_text:
            self.last_text = text
            self.last_time = now
            return True
        elif elapsed > 6.5: # Si el entorno sigue igual, repite con calma tras 6.5 segundos
            self.last_text = text
            self.last_time = now
            return True

        return False


class VisionServer:
    def __init__(self):
        self.detector = YoloDetector()
        self.ground_detector = GroundHazardDetector()
        self.fallback = FallbackDetector()
        self.translator = TranslationService()
        self.analyser = SpatialAnalyser(self.translator)
        self.synthesizer = SceneSynthesizer()
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

            # 1. Detección semántica (COCO 80 + Obstáculos)
            detections = self.detector.detect(frame)

            # 2. Detección de huecos / desniveles en el suelo (filtrando objetos conocidos)
            ground_hazards = self.ground_detector.detect(frame, existing_detections=detections)
            detections.extend(ground_hazards)

            # 3. Respaldo de pared frontal si nada fue detectado
            if not detections:
                detections = self.fallback.detect_wall(frame)

            analysed = [self.analyser.analyse(d["label"], d["box"], w, h) for d in detections]

            # 4. Sintetizar la descripción panorámica de todo el entorno
            scene_desc, scene_risk, active_advice = self.synthesizer.synthesize(analysed)

            # 5. Renderizado PC en tiempo real ("Riqsi Monitor")
            for obj in analysed:
                color = (0, 0, 255) if obj["risk"] == "Alto" else ((0, 165, 255) if obj["risk"] == "Medio" else (0, 255, 0))
                cv2.rectangle(frame, (obj["box"][0], obj["box"][1]), (obj["box"][2], obj["box"][3]), color, 2)
                cv2.putText(frame, f"{obj['label']}", (obj["box"][0], max(22, obj["box"][1] - 8)),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)

            # Barra HUD inferior con la descripción completa del entorno
            banner_color = (0, 0, 180) if scene_risk == "Alto" else ((0, 120, 200) if scene_risk == "Medio" else (35, 120, 35))
            cv2.rectangle(frame, (0, h - 45), (w, h), (15, 15, 15), -1)
            cv2.rectangle(frame, (0, h - 45), (8, h), banner_color, -1)
            cv2.putText(frame, f"ENTORNO: {scene_desc}", (16, h - 16),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.50, (255, 255, 255), 2)

            try:
                cv2.imshow("Riqsi Monitor", frame)
                cv2.waitKey(1)
            except Exception:
                pass

            if analysed:
                allow_voice = self.debouncer.should_announce(scene_desc, scene_risk)
                top = analysed[0]

                payload = {
                    "type": "detection",
                    "label": top["label"],
                    "position": top["pos"],
                    "risk": scene_risk,
                    "distancia": top["distancia"],
                    "description": scene_desc,
                    "announce_voice": allow_voice,
                    "frame_width": w,
                    "frame_height": h,
                    "objects": analysed[:10]
                }
                if allow_voice:
                    print(f"[VOZ ENTORNO] {scene_desc}", flush=True)

                await websocket.send(json.dumps(payload))
            else:
                await websocket.send(json.dumps({"type": "clear"}))

        except Exception as e:
            print(f"[ERROR FRAME] {e}", flush=True)
        finally:
            self.is_processing = False

    async def handler(self, websocket):
        print(f"[CONECTADO DESDE CELULAR] {websocket.remote_address}", flush=True)
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
    print(f"\n=======================================================")
    print(f"   RIQSI CORE - SISTEMA DE VISIÓN Y GUÍA ESPACIAL")
    print(f"   Puerto: {PORT} | Modelos: YOLOv8 + Detección de Suelo")
    print(f"=======================================================\n")
    async with websockets.serve(server.handler, "0.0.0.0", PORT):
        while True:
            await asyncio.sleep(3600)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass