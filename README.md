# Riqsi - Asistente de Visión Inteligente 👁️📱

Riqsi es un asistente inteligente de visión del entorno para personas con discapacidad visual. Esta versión utiliza una arquitectura híbrida de visión artificial: la cámara del celular envía imágenes a la PC, que las analiza con OpenCV y YOLOv8 y devuelve las detecciones en tiempo real al teléfono a través de WebSockets, donde el usuario escucha la descripción por voz (TTS real) y siente la vibración.

---

## 🛠️ Requisitos de Instalación (PC)

El **celular envía su cámara** al servidor que corre en tu PC; la PC ejecuta YOLOv8 y devuelve las detecciones al teléfono.

1. Asegúrate de tener instalado **Python 3.10+**.
2. Instala las dependencias del servidor desde la raíz del proyecto:
   ```bash
   pip install -r server/requirements.txt
   ```
   *(Los modelos `yolov8n.pt` y `best.pt` ya vienen en la raíz del repositorio.)*

---

## 🚀 Guía de Ejecución Paso a Paso

### 1. Iniciar el Servidor de Visión (PC)
```bash
python server/detector.py
```
El servidor escucha en el puerto **8765** y atiende a **un solo celular a la vez** (si se conecta otro, se cierra el anterior).

* **Token opcional:** define la variable de entorno `RIQSI_TOKEN` antes de iniciar y el servidor exigirá `?token=...` en la URL de conexión. Si no la defines, acepta conexiones como siempre (la app aún no envía token).
* **Monitor opcional:** `python server/detector.py --monitor` (o `RIQSI_MONITOR=1`) abre una ventana "Riqsi Monitor" para depurar lo que ve el servidor. Por defecto está apagado.
* **Pruebas:** `python -m pytest server/tests -q`

---

### 2. Conectar el Cliente Móvil (Celular)
1. Conecta tu celular y tu PC a la **misma red Wi-Fi**.
2. Obtén la **dirección IP local** de tu PC (en Windows abre `cmd` y escribe `ipconfig`, busca la dirección IPv4, por ejemplo `192.168.1.15`).
3. En la aplicación Riqsi en tu teléfono móvil:
   * Ve a la pestaña **Perfil** (tercer icono abajo).
   * Selecciona la opción **Servidor IP** e ingresa la dirección IP de tu PC.
   * Guarda los cambios.
4. Regresa a la pestaña **Inicio** y presiona el gran botón de play central.
5. ¡Listo! La cámara de tu celular se enviará a la PC, que analizará cada imagen. El teléfono **reproducirá el audio en voz alta en español** y **vibrará** cuando haya un obstáculo cerca.
