# Riqsi - Asistente de Visión Inteligente 👁️📱

Riqsi es un asistente inteligente de visión del entorno para personas con discapacidad visual. Detecta obstáculos (personas, autos, puertas, etc.) con la cámara del celular y avisa **por voz en español** y **por vibración** según qué tan cerca están. También incluye un mapa con **GPS real** y rutas a pie guiadas por voz.

---

## ⚙️ Cómo funciona ahora

Toda la detección corre **dentro del celular**, sin PC, sin servidor y sin Wi-Fi. La app incluye un modelo **YOLOv8 propio de 13 clases** (`assets/models/best.tflite`, clases en `assets/labels.txt`: Barandas, Billete, LLave, Laptop, Lentes, Mesa, Mochila, PC, Persona, Puerta, Silla, Tacho, escaleras) y lo ejecuta con el plugin oficial [`ultralytics_yolo`](https://pub.dev/packages/ultralytics_yolo). Solo el mapa y las rutas necesitan internet.

```
  Cámara del celular
         │
         ▼
  YOLOv8 propio en el teléfono (best.tflite, ultralytics_yolo, sin internet)
         │  objetos + posición + distancia estimada
         ▼
  Voz en español (TTS)  +  Vibración según la distancia

  Mapa:  GPS (geolocator) ─► Nominatim (buscar lugares)
                          ─► OSRM routing.openstreetmap.de (ruta a pie)
                          ─► guía por voz   [requiere internet]
```

---

## 📲 Instalar y ejecutar la app

Requisitos: **Flutter** instalado y un celular Android (recomendado) con la depuración USB activada.

```bash
flutter pub get
flutter run                 # ejecuta en el celular conectado
flutter build apk --release # genera el APK en build/app/outputs/flutter-apk/
```

**Permisos** que pedirá la app la primera vez:
* 📷 **Cámara**: para detectar obstáculos.
* 📍 **Ubicación**: para el mapa, "¿Dónde estoy?" y la guía de rutas.

---

## 🧭 Uso

### Inicio
* Presiona el gran botón central para **iniciar** o **detener** la detección.
* La app **dice en voz alta** lo que detecta (por ejemplo "persona cerca") y **vibra** según la distancia: cuanto más cerca está el obstáculo, más rápida e intensa es la vibración.

### Mapa
* **Buscar** un lugar (Nominatim / OpenStreetMap) y elegir el resultado.
* **Ruta a pie** hasta el destino, con indicaciones por voz paso a paso.
* Botón **"¿Dónde estoy?"**: la app dice tu ubicación actual por voz.

### Perfil
* **Voz**: elegir la voz del lector.
* **Volumen** de la voz.
* **Vibración**: activar/desactivar o ajustar la intensidad.

---

## ♿ Accesibilidad

Riqsi está pensada para usarse con **TalkBack** (Android) activado: los botones y pantallas tienen etiquetas semánticas, y la información importante se comunica también por voz y vibración, no solo visualmente.

---

## ⚠️ Limitaciones honestas

* La **distancia es estimada** y no está calibrada: úsala como referencia, no como medida exacta.
* Necesita **buena luz**; con poca luz o la cámara tapada la detección falla.
* **El modelo no tiene clase "pared"**: por eso la app nunca dice "camino despejado". Si no ve nada conocido dice "No detecto objetos conocidos" (sin voz), porque una pared o un muro no se detectan. Para evitar falsas alarmas un objeto debe verse en 3 cuadros seguidos, cada clase tiene su confianza mínima (escaleras 0.60, alerta Alto solo desde 0.65) y se ignoran cajas diminutas o que cubren toda la imagen.
* El modelo propio (`best.tflite`) **solo se usa en Android**. En iOS la app sigue usando YOLO11n COCO hasta exportar `best.pt` a Core ML (`yolo export model=best.pt format=coreml`) y cambiar `riqsiModelPath`.
* Para cambiar de modelo: reemplaza `assets/models/best.tflite` y `assets/labels.txt` (una clase por línea, en el orden del modelo). El riesgo de cada clase se define en `scene_logic.dart` (`_highRiskKeys`, `_obstacleKeys`); el resto se anuncia como objeto.
* El **mapa y las rutas necesitan datos/internet**, y la precisión depende del GPS y de la cobertura de OpenStreetMap.
* No reemplaza al bastón ni a otras ayudas de movilidad.

---

## 👥 Para el equipo: carpeta `server/` (opcional)

La carpeta `server/` **ya no la usa la app**. Se conserva solo como herramienta del equipo para pruebas y entrenamiento (detector en PC con OpenCV + YOLO por WebSocket).

```bash
pip install -r server/requirements.txt
python server/detector.py          # escucha en el puerto 8765
python -m pytest server/tests -q   # pruebas
```
*(Los modelos `yolov8n.pt` y `best.pt` están en la raíz del repositorio.)*

### Servidor (opcional)

Opciones: `RIQSI_TOKEN` exige `?token=...` en la conexión; `--monitor` (o `RIQSI_MONITOR=1`) abre una ventana de depuración; `--port` cambia el puerto.

| Síntoma | Qué hacer |
|---|---|
| `ModuleNotFoundError: No module named 'ultralytics'` (o `cv2`, `numpy`) | `pip install -r server/requirements.txt` |
| `No se pudo abrir el puerto 8765` | Cierra el otro servidor o usa `--port 8766` |
| Un cliente no conecta | Revisa la IP, el **Firewall de Windows** (permitir Python en redes privadas) y que la red no aísle los dispositivos |

---

## 📜 Licencia y atribuciones

* **AGPL-3.0**: `ultralytics` y sus modelos (YOLO) están bajo licencia AGPL-3.0, por lo que este proyecto se distribuye bajo los mismos términos.
* Mapas y búsqueda: © colaboradores de **OpenStreetMap** (datos bajo ODbL), mediante Nominatim.
* Rutas a pie: **OSRM** con el servidor `routing.openstreetmap.de`.
