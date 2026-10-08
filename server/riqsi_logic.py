"""Lógica pura del servidor RIQSI (solo biblioteca estándar, sin cv2/numpy/ultralytics).

Se separa de detector.py para poder probarla con pytest sin dependencias pesadas.
"""
from __future__ import annotations

from collections import Counter

# ---------------------------------------------------------------------------
# Contrato con la app Flutter
# ---------------------------------------------------------------------------
VALID_DISTANCIAS = ("muy_cerca", "cerca", "lejos", "despejado")
RISK_ORDER = {"Bajo": 0, "Medio": 1, "Alto": 2}
DIST_ORDER = {"despejado": -1, "lejos": 0, "cerca": 1, "muy_cerca": 2}
LEVELS = ("lejos", "cerca", "muy_cerca")

# ---------------------------------------------------------------------------
# Etiquetas, traducciones y plurales
# ---------------------------------------------------------------------------
TRANSLATIONS = {
    # Vía pública / Tráfico / Señalética
    "traffic_light": "semáforo", "stop_sign": "señal de pare",
    "fire_hydrant": "hidrante", "parking_meter": "parquímetro",
    "bench": "banca", "pole": "poste", "reflective_cone": "cono de seguridad",
    "spherical_roadblock": "bolardo", "warning_column": "columna",
    "ashcan": "tacho de basura", "crosswalk": "paso peatonal",
    # Personas y animales
    "person": "persona", "pedestrian": "peatón", "dog": "perro", "cat": "gato",
    "bird": "ave", "horse": "caballo", "sheep": "oveja", "cow": "vaca",
    # Vehículos
    "car": "auto", "bus": "autobús", "truck": "camión", "motorcycle": "motocicleta",
    "bicycle": "bicicleta", "tricycle": "triciclo",
    "train": "tren", "airplane": "avión", "boat": "bote",
    # Accesorios y objetos personales
    "backpack": "mochila", "umbrella": "paraguas", "handbag": "bolso",
    "tie": "corbata", "suitcase": "maleta", "bottle": "botella", "cup": "taza",
    "cell_phone": "teléfono", "keyboard": "teclado", "mouse": "ratón",
    "sign": "señal", "traffic_sign": "señal de tránsito",
    # Peligros en el suelo
    "hole": "hueco", "pothole": "hueco", "hueco": "hueco", "desnivel": "desnivel",
    "stairs": "escaleras", "door": "puerta", "wall": "pared", "pared": "pared",
    # Interiores y muebles
    "chair": "silla", "couch": "sillón", "bed": "cama", "dining_table": "mesa",
    "tv": "pantalla", "laptop": "computadora portátil", "refrigerator": "refrigerador",
    "potted_plant": "planta", "sink": "lavamanos",
}

ALIASES = {"motorbike": "motorcycle", "potholes": "pothole"}

# Plurales irregulares o que las reglas no resuelven bien.
PLURAL_OVERRIDES = {
    "autobús": "autobuses",
    "paraguas": "paraguas",
    "escaleras": "escaleras",
    "lavamanos": "lavamanos",
    "computadora portátil": "computadoras portátiles",
    "tacho de basura": "tachos de basura",
}

HOLE_KEYS = {"hueco", "desnivel", "pothole", "hole"}
VEHICLE_KEYS = {"car", "bus", "truck", "motorcycle", "tricycle"}
# Objetos que informan pero no estorban el paso: no se da consejo de esquive.
NON_OBSTRUCTIVE_KEYS = {"traffic_light", "stop_sign", "traffic_sign", "sign", "crosswalk"}


def normalize_label(label: str) -> str:
    """Clave de clase canónica: minúsculas, '_' en vez de espacios, alias unificados."""
    clean = str(label).lower().strip().replace(" ", "_")
    return ALIASES.get(clean, clean)


def translate(label: str) -> str:
    clean = str(label).lower().strip()
    if clean.isdigit() or clean.startswith("0000"):
        return "obstáculo"
    key = normalize_label(clean)
    return TRANSLATIONS.get(key, clean.replace("_", " "))


_ACCENT_STRIP = str.maketrans("áéíóú", "aeiou")


def _pluralize_word(word: str) -> str:
    if word in PLURAL_OVERRIDES:
        return PLURAL_OVERRIDES[word]
    if not word:
        return word
    if word.endswith("ón"):
        return word[:-2] + "ones"
    if word.endswith("z"):
        return word[:-1] + "ces"
    if word.endswith("s"):
        return word  # ya es plural o invariable (escaleras, paraguas)
    if word[-1] in "aeiouáéíóú":
        return word + "s"
    return word + "es"


def pluralize(name: str) -> str:
    """Plural en español de un nombre (puede ser compuesto: 'señal de pare')."""
    name = name.lower().strip()
    if name in PLURAL_OVERRIDES:
        return PLURAL_OVERRIDES[name]
    words = name.split(" ")
    if len(words) > 1:
        if "de" in words:
            idx = words.index("de")
            head = " ".join(words[:idx])
            return " ".join([pluralize(head)] + words[idx:])
        return " ".join(_pluralize_word(w) for w in words)
    return _pluralize_word(name)


# ---------------------------------------------------------------------------
# Geometría
# ---------------------------------------------------------------------------
def iou(a, b) -> float:
    xa, ya = max(a[0], b[0]), max(a[1], b[1])
    xb, yb = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, xb - xa) * max(0, yb - ya)
    area_a = max(0, a[2] - a[0]) * max(0, a[3] - a[1])
    area_b = max(0, b[2] - b[0]) * max(0, b[3] - b[1])
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def nms_merge(detections: list, iou_thr: float = 0.5) -> list:
    """Elimina duplicados (misma clase normalizada, IoU > umbral): gana la mayor confianza."""
    ordered = sorted(detections, key=lambda d: d.get("confidence", 0.0), reverse=True)
    kept = []
    for d in ordered:
        key = normalize_label(d["label"])
        if any(normalize_label(k["label"]) == key and iou(k["box"], d["box"]) > iou_thr for k in kept):
            continue
        kept.append(d)
    return kept


# ---------------------------------------------------------------------------
# Confirmación de heurísticas (pared / hueco) en N frames consecutivos
# ---------------------------------------------------------------------------
class HazardConfirmer:
    def __init__(self, frames_required: int = 3):
        self.n = frames_required
        self.counts: dict = {}

    def confirm(self, hazards: list, frame_w: int) -> list:
        seen = {}
        for h in hazards:
            b = h["box"]
            xc = ((b[0] + b[2]) / 2.0) / float(frame_w)
            bucket = 0 if xc < 0.38 else (2 if xc > 0.62 else 1)
            seen.setdefault((normalize_label(h["label"]), bucket), h)
        new_counts = {k: self.counts.get(k, 0) + 1 for k in seen}
        self.counts = new_counts
        return [h for k, h in seen.items() if new_counts[k] >= self.n]


# ---------------------------------------------------------------------------
# Distancia / riesgo / posición con suavizado
# ---------------------------------------------------------------------------
def _level_index(area: float, bottom: float, scale: float) -> int:
    if (bottom > 0.85 * scale and area > 0.20 * scale) or area > 0.50 * scale:
        return 2
    if bottom > 0.60 * scale or area > 0.10 * scale:
        return 1
    return 0


def _hysteresis(prev: int | None, fn) -> int:
    """fn(scale) -> nivel. Para subir hay que superar umbrales +10 %; para bajar, bajar de -10 %."""
    base = fn(1.0)
    if prev is None:
        return base
    up, down = fn(1.1), fn(0.9)
    if up > prev:
        return up
    if down < prev:
        return down
    return prev


def pos_with_hysteresis(x_center: float, prev: str | None, margin: float = 0.04) -> str:
    lo, hi = 0.38, 0.62
    if prev == "Izquierda":
        lo += margin
    elif prev in ("Adelante", "Derecha"):
        lo -= margin
    if prev == "Derecha":
        hi -= margin
    elif prev in ("Adelante", "Izquierda"):
        hi += margin
    if x_center < lo:
        return "Izquierda"
    if x_center > hi:
        return "Derecha"
    return "Adelante"


class _Track:
    def __init__(self, key, box, area, bottom, xc):
        self.key = key
        self.box = box
        self.area = area
        self.bottom = bottom
        self.xc = xc
        self.level: int | None = None
        self.pos: str | None = None
        self.hole_level: int | None = None
        self.missed = 0


class SpatialTracker:
    """Analiza detecciones por frame. Estado por conexión.

    NOTA: la distancia es una HEURÍSTICA basada en el tamaño del recuadro y su borde
    inferior; NO está calibrada con la cámara real ni con distancias medidas en metros.
    Se suaviza con EMA por objeto (emparejado por clase + IoU) y con histéresis entre
    umbrales para evitar saltos cerca <-> lejos.
    """

    EMA_ALPHA = 0.5
    MATCH_IOU = 0.3
    MAX_MISSED = 5

    def __init__(self):
        self.tracks: list[_Track] = []

    def _match(self, detections, w, h):
        pairs = []
        for i, d in enumerate(detections):
            key = normalize_label(d["label"])
            for j, t in enumerate(self.tracks):
                if t.key == key:
                    v = iou(d["box"], t.box)
                    if v > self.MATCH_IOU:
                        pairs.append((v, i, j))
        pairs.sort(reverse=True)
        used_d, used_t, result = set(), set(), {}
        for _, i, j in pairs:
            if i in used_d or j in used_t:
                continue
            used_d.add(i)
            used_t.add(j)
            result[i] = self.tracks[j]
        return result

    def analyse_frame(self, detections: list, w: int, h: int) -> list:
        matches = self._match(detections, w, h)
        matched_tracks = set(id(t) for t in matches.values())
        out = []
        new_tracks = []
        for i, d in enumerate(detections):
            x1, y1, x2, y2 = d["box"]
            area = max(0, (x2 - x1)) * max(0, (y2 - y1)) / float(w * h)
            bottom = y2 / float(h)
            xc = ((x1 + x2) / 2.0) / float(w)
            t = matches.get(i)
            if t is None:
                t = _Track(normalize_label(d["label"]), d["box"], area, bottom, xc)
                new_tracks.append(t)
            else:
                a = self.EMA_ALPHA
                t.area = a * area + (1 - a) * t.area
                t.bottom = a * bottom + (1 - a) * t.bottom
                t.xc = a * xc + (1 - a) * t.xc
                t.box = d["box"]
                t.missed = 0
            out.append(self._classify(d, t, w, h))
        for t in self.tracks:
            if id(t) not in matched_tracks:
                t.missed += 1
        self.tracks = [t for t in self.tracks if t.missed <= self.MAX_MISSED] + new_tracks
        return out

    def _classify(self, d: dict, t: _Track, w: int, h: int) -> dict:
        label = d["label"]
        key = t.key
        box = d["box"]
        x1, y1, x2, y2 = box

        t.pos = pos_with_hysteresis(t.xc, t.pos)
        pos = t.pos
        trans = translate(label)
        trans_label = trans.capitalize()
        pos_desc = "adelante" if pos == "Adelante" else f"a la {pos.lower()}"
        is_wall = key in ("pared", "wall")
        is_hole = key in HOLE_KEYS
        non_obstructive = key in NON_OBSTRUCTIVE_KEYS
        area, bottom = t.area, t.bottom

        t.level = _hysteresis(t.level, lambda s: _level_index(area, bottom, s))
        level = LEVELS[t.level]

        if is_wall or area > 0.60:
            consejo = "Paso bloqueado. Detente"
        elif non_obstructive:
            consejo = ""
        elif pos == "Adelante":
            consejo = "Muévete al lado derecho" if t.xc <= 0.50 else "Muévete al lado izquierdo"
        elif pos == "Izquierda":
            consejo = "Mantente a la derecha"
        else:
            consejo = "Mantente a la izquierda"
        advice_txt = f" {consejo}." if consejo else ""

        if is_hole:
            risk = "Alto"
            t.hole_level = _hysteresis(t.hole_level, lambda s: 1 if bottom > 0.70 * s else 0)
            distancia = "muy_cerca" if t.hole_level == 1 else "cerca"
            desc = f"Hueco adelante en el suelo.{advice_txt}"
        elif is_wall:
            risk = "Alto"
            distancia = "muy_cerca"
            desc = "Pared frontal muy cerca. Detente."
        elif non_obstructive:
            risk = "Bajo"
            distancia = "lejos" if level == "lejos" else "cerca"
            desc = f"{trans_label} {pos_desc}."
        elif level == "muy_cerca":
            risk = "Alto" if key in VEHICLE_KEYS else "Medio"
            distancia = "muy_cerca"
            desc = f"{trans_label} muy cerca {pos_desc}.{advice_txt}"
        elif level == "cerca":
            risk = "Medio"
            distancia = "cerca"
            desc = f"{trans_label} cerca {pos_desc}."
        else:
            risk = "Bajo"
            distancia = "lejos"
            desc = f"{trans_label} {pos_desc}."

        box_norm = [
            round(x1 / float(w), 4), round(y1 / float(h), 4),
            round(x2 / float(w), 4), round(y2 / float(h), 4),
        ]
        return {
            "label": trans_label,
            "clase": key,
            "pos": pos,
            "position": pos,
            "risk": risk,
            "distancia": distancia,
            "proximity_ratio": round(area, 3),
            "consejo": consejo,
            "desc": desc,
            "confidence": round(float(d.get("confidence", 0.0)), 3),
            "box": box,
            "box_norm": box_norm,
        }


# ---------------------------------------------------------------------------
# Prioridad, escena y payload
# ---------------------------------------------------------------------------
def priority_key(o: dict):
    return (RISK_ORDER.get(o["risk"], 0), DIST_ORDER.get(o["distancia"], 0), o.get("proximity_ratio", 0.0))


def sort_by_priority(objs: list) -> list:
    return sorted(objs, key=priority_key, reverse=True)


def pick_top(objs: list) -> dict:
    return max(objs, key=priority_key)


def max_risk(*risks: str) -> str:
    return max(risks, key=lambda r: RISK_ORDER.get(r, 0))


def _join(items: list) -> str:
    return ", ".join(items[:-1]) + " y " + items[-1] if len(items) > 1 else items[0]


def _group(labels: list) -> str:
    items = []
    for k, c in Counter(labels).items():
        items.append(f"{c} {pluralize(k)}" if c > 1 else k)
    return _join(items)


def synthesize(objs: list) -> tuple:
    """Devuelve (descripción, riesgo de escena, consejo)."""
    if not objs:
        return "Camino despejado al frente.", "Bajo", "Vía libre"

    ordered = sort_by_priority(objs)
    critical = [o for o in ordered if o["risk"] == "Alto"]
    if critical:
        c = critical[0]
        consejo = c.get("consejo") or "Detente"
        clase = c.get("clase", c["label"].lower())
        if clase in HOLE_KEYS:
            desc = f"¡Cuidado! Hueco adelante en el suelo. {consejo}."
        elif clase in ("pared", "wall"):
            desc = "¡Atención! Pared al frente. Detente."
        else:
            pos = c["pos"]
            where = "adelante" if pos == "Adelante" else f"a la {pos.lower()}"
            desc = f"¡Cuidado! {c['label']} muy cerca {where}. {consejo}."
        return desc, "Alto", consejo

    pos_map = {"Adelante": [], "Izquierda": [], "Derecha": []}
    for o in ordered:
        if o.get("pos", "Adelante") in pos_map:
            pos_map[o.get("pos", "Adelante")].append(o["label"].lower())

    sections = []
    if pos_map["Adelante"]:
        sections.append("Al frente " + _group(pos_map["Adelante"]))
    if pos_map["Derecha"]:
        sections.append(_group(pos_map["Derecha"]) + " a la derecha")
    if pos_map["Izquierda"]:
        sections.append(_group(pos_map["Izquierda"]) + " a la izquierda")
    full_desc = ". ".join(sections).capitalize() + "."

    front = [o for o in ordered if o.get("pos") == "Adelante" and o.get("risk") == "Medio" and o.get("consejo")]
    if front:
        advice = front[0]["consejo"]
        full_desc += f" {advice}."
        return full_desc, "Medio", advice
    return full_desc, "Bajo", "Vía despejada"


class SpeechDebouncer:
    """Regula el TTS. Estado por conexión; reloj inyectable para pruebas."""

    ALTO_COOLDOWN = 2.5
    CHANGE_COOLDOWN = 3.8
    REPEAT_COOLDOWN = 6.5

    def __init__(self):
        self.last_sig: frozenset = frozenset()
        self.last_time = float("-inf")
        self.alto_last: dict = {}

    @staticmethod
    def _key(o: dict):
        return (o.get("clase") or o["label"].lower(), o.get("pos", "Adelante"))

    def should_announce(self, objs: list, risk: str, now: float) -> bool:
        keys = frozenset(self._key(o) for o in objs)
        alto_keys = {self._key(o) for o in objs if o["risk"] == "Alto"}

        if risk == "Alto" or alto_keys:
            due = [k for k in alto_keys if now - self.alto_last.get(k, float("-inf")) >= self.ALTO_COOLDOWN]
            # limpiar claves viejas
            self.alto_last = {k: v for k, v in self.alto_last.items() if now - v < 30}
            if due:
                for k in due:
                    self.alto_last[k] = now
                self.last_sig, self.last_time = keys, now
                return True
            return False

        elapsed = now - self.last_time
        if keys != self.last_sig and elapsed > self.CHANGE_COOLDOWN:
            self.last_sig, self.last_time = keys, now
            return True
        if elapsed > self.REPEAT_COOLDOWN:
            self.last_sig, self.last_time = keys, now
            return True
        return False


def build_payload(analysed: list, scene_desc: str, scene_risk: str, allow_voice: bool,
                  frame_w: int, frame_h: int) -> dict:
    if not analysed:
        return {"type": "clear"}
    ordered = sort_by_priority(analysed)
    top = ordered[0]
    return {
        "type": "detection",
        "label": top["label"],
        "position": top["pos"],
        "risk": max_risk(scene_risk, top["risk"]),
        "distancia": top["distancia"],
        "description": scene_desc,
        "announce_voice": allow_voice,
        "frame_width": frame_w,
        "frame_height": frame_h,
        "objects": ordered[:10],
    }
