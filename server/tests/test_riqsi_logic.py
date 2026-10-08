import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from riqsi_logic import (  # noqa: E402
    VALID_DISTANCIAS, HazardConfirmer, SpatialTracker, SpeechDebouncer,
    build_payload, nms_merge, pick_top, pluralize, pos_with_hysteresis, synthesize,
)

W, H = 640, 480


def det(label, box, conf=0.8):
    return {"label": label, "box": box, "confidence": conf}


def analyse(dets, tracker=None):
    return (tracker or SpatialTracker()).analyse_frame(dets, W, H)


BIG = [100, 100, 540, 475]      # muy cerca
SMALL = [300, 200, 330, 240]    # lejos


def test_hueco_muy_cerca():
    o = analyse([det("hueco", [250, 380, 400, 470])])[0]
    assert o["distancia"] == "muy_cerca" and o["risk"] == "Alto"
    o2 = analyse([det("hueco", [250, 280, 400, 330])])[0]
    assert o2["distancia"] == "cerca"


def test_distancia_siempre_valida():
    labels = ["hueco", "pared", "car", "person", "traffic light", "pole", "000000000540"]
    boxes = [BIG, SMALL, [0, 0, 640, 480], [10, 400, 60, 470], [300, 100, 340, 300]]
    for l in labels:
        for b in boxes:
            o = analyse([det(l, b)])[0]
            assert o["distancia"] in VALID_DISTANCIAS


def test_top_es_el_mas_peligroso():
    objs = analyse([det("person", SMALL), det("car", BIG), det("pole", [300, 300, 340, 420])])
    assert pick_top(objs)["clase"] == "car"
    payload = build_payload(objs, "x", "Alto", True, W, H)
    assert payload["label"] == "Auto" and payload["objects"][0]["clase"] == "car"


def test_vehiculo_muy_cerca_es_alto():
    for c in ("car", "bus", "truck", "motorbike"):
        o = analyse([det(c, BIG)])[0]
        assert o["distancia"] == "muy_cerca" and o["risk"] == "Alto"
    assert analyse([det("person", BIG)])[0]["risk"] == "Medio"
    desc, risk, _ = synthesize(analyse([det("car", BIG)]))
    assert risk == "Alto" and "Auto" in desc


def test_nms_elimina_duplicado_entre_modelos():
    a = det("motorcycle", [100, 100, 200, 200], 0.6)
    b = det("motorbike", [105, 102, 203, 198], 0.9)
    c = det("car", [100, 100, 200, 200], 0.5)
    out = nms_merge([a, b, c])
    assert len(out) == 2
    assert [d for d in out if d["label"] == "motorbike"][0]["confidence"] == 0.9


def test_historesis_posicion_no_alterna():
    pos = None
    seen = []
    for x in [0.36, 0.40, 0.37, 0.40, 0.39, 0.37]:
        pos = pos_with_hysteresis(x, pos)
        seen.append(pos)
    assert len(set(seen)) == 1
    assert pos_with_hysteresis(0.10, "Adelante") == "Izquierda"
    assert pos_with_hysteresis(0.90, "Adelante") == "Derecha"


def test_historesis_distancia_no_salta():
    t = SpatialTracker()
    levels = []
    # area oscila alrededor del umbral 0.10 (bottom bajo)
    for h in [32, 31, 32, 30, 32, 31]:
        o = t.analyse_frame([det("pole", [300, 0, 300 + h * 4, h * 8])], W, H)[0]
        levels.append(o["distancia"])
    assert len(set(levels)) == 1


def test_cooldown_alto():
    d = SpeechDebouncer()
    car = analyse([det("car", BIG)])
    assert d.should_announce(car, "Alto", 100.0)
    assert not d.should_announce(car, "Alto", 101.0)
    assert d.should_announce(car, "Alto", 102.6)
    # objeto Alto nuevo: inmediato
    hole = analyse([det("hueco", [250, 380, 400, 470])])
    assert d.should_announce(car + hole, "Alto", 102.7)


def test_repeticion_escena():
    d = SpeechDebouncer()
    s = analyse([det("person", SMALL)])
    assert d.should_announce(s, "Bajo", 100.0)
    assert not d.should_announce(s, "Bajo", 104.5)
    assert d.should_announce(s, "Bajo", 106.6)


def test_plurales():
    assert pluralize("pared") == "paredes"
    assert pluralize("camión") == "camiones"
    assert pluralize("señal de pare") == "señales de pare"
    assert pluralize("autobús") == "autobuses"
    assert pluralize("persona") == "personas"
    desc, _, _ = synthesize(analyse([
        det("truck", [10, 200, 60, 260]), det("truck", [90, 200, 140, 260])]))
    assert "camiones" in desc


def test_sin_consejo_para_semaforo():
    o = analyse([det("traffic light", [300, 100, 330, 160])])[0]
    assert o["consejo"] == "" and o["risk"] == "Bajo"
    desc, risk, advice = synthesize([o])
    assert "Muévete" not in desc and risk == "Bajo"


def test_confirmacion_heuristica():
    c = HazardConfirmer(3)
    h = [det("pared", [64, 48, 576, 432])]
    assert c.confirm(h, W) == []
    assert c.confirm(h, W) == []
    assert len(c.confirm(h, W)) == 1
    assert c.confirm([], W) == []
    assert c.confirm(h, W) == []


def test_payload_contrato():
    objs = analyse([det("car", BIG)])
    p = build_payload(objs, "desc", "Alto", True, W, H)
    for k in ("type", "label", "position", "risk", "distancia", "description",
              "announce_voice", "frame_width", "frame_height", "objects"):
        assert k in p
    for k in ("label", "pos", "risk", "distancia", "box", "box_norm"):
        assert k in p["objects"][0]
    assert build_payload([], "", "Bajo", False, W, H) == {"type": "clear"}
