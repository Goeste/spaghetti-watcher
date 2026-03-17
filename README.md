# bambicam

RTSP camera stream for Raspberry Pi Zero 2 W, optimized for BambuLab 3D printer monitoring with [Obico](https://github.com/TheSpaghettiDetective/obico-server) spaghetti detection.

## What it does

Turns a Raspberry Pi Zero 2 W with a Pi camera into a reliable RTSP camera stream that can be consumed by [Frigate NVR](https://frigate.video/), [Obico](https://www.obico.io/) spaghetti detection, or any RTSP client.

```
Pi Zero 2 W + Pi Camera ──RTSP──→ Frigate NVR (Livestream & Recording)
                          └──RTSP──→ Spaghetti Watcher → Obico ML API
                                                       → Pushsafer (Notification)
                                                       → BambuLab MQTT (Auto-Pause)
```

## Features

- **Optimized for Pi Zero 2 W** – uses `rpicam-vid` + `ffmpeg` pipeline instead of MediaMTX's built-in `rpiCamera` source to avoid `/dev/shm` memory exhaustion
- **Interactive setup** – asks for camera module and mount orientation during installation
- **BambuLab P1S tuned** – image settings optimized for 3D printer monitoring (contrast, sharpness, white balance for LED lighting)
- **Auto-recovery** – SHM watchdog cleans up memory leaks, 6-hour reboot cronjob
- **Swap & SSH keepalive** – prevents OOM freezes and SSH disconnects

## Supported cameras

| Camera | Resolution | FPS | Autofocus |
|--------|-----------|-----|-----------|
| Camera Module v3 Wide (recommended) | 1280x720 | 10 | Manual (preset ~33cm) |
| Camera Module v3 | 1280x720 | 10 | Manual (preset ~33cm) |
| Camera Module v2 | 1280x720 | 10 | No (fixed focus) |
| Arducam IMX219 Wide | 1280x720 | 10 | No (fixed focus) |
| Camera Module v1 | 1280x720 | 8 | No (fixed focus) |

## Prerequisites

- Raspberry Pi Zero 2 W with Raspberry Pi OS Bookworm (64-bit Lite)
- Pi Camera connected via ribbon cable
- Network connectivity (Wi-Fi)

## Installation

```bash
git clone https://github.com/YOUR_USER/bambicam.git
cd bambicam
chmod +x setup.sh
sudo ./setup.sh
```

The setup script will ask for your camera module and mount orientation:

```
Welches Kamera-Modul nutzt du?

  1) Camera Module v3 Wide  (IMX708, 12MP, AF, 120° FOV) ← empfohlen
  2) Camera Module v3       (IMX708, 12MP, AF, 66° FOV)
  3) Camera Module v2       (IMX219, 8MP, Fixfokus)
  4) Arducam IMX219 Wide    (8MP, Fixfokus, Weitwinkel)
  5) Camera Module v1       (OV5647, 5MP, Fixfokus)

Wie ist die Kamera montiert?

  1) Normal   – Kamera aufrecht, Ribbon-Kabel nach unten
  2) Gedreht  – Kamera 180° kopfüber (typisch bei Corner-Mounts)
```

Non-interactive mode:

```bash
sudo CAMERA_MODULE=v3wide MOUNT_ORIENTATION=normal ./setup.sh
```

## After installation

The stream is available at:

```
rtsp://<PI-IP>:8554/cam
```

Test with ffplay:

```bash
ffplay -rtsp_transport tcp rtsp://<PI-IP>:8554/cam
```

### Frigate configuration

```yaml
cameras:
  bambulab_p1s:
    ffmpeg:
      inputs:
        - path: rtsp://<PI-IP>:8554/cam
          roles: [detect, record]
      input_args: preset-rtsp-restream
    detect:
      enabled: true
      width: 1280
      height: 720
      fps: 5
    record:
      enabled: true
      retain:
        days: 3
        mode: motion
```

## Spaghetti detection

For AI-based print failure detection, see the [spaghetti-watcher](spaghetti-watcher/) directory. It runs on a separate server (not the Pi!) and uses the [Obico ML API](https://github.com/TheSpaghettiDetective/obico-server) to analyze snapshots from the camera stream.

Features:
- Pushsafer notifications with snapshot image
- Automatic print pause via BambuLab MQTT
- Configurable confidence thresholds

```bash
cd spaghetti-watcher
chmod +x spaghetti-watcher-setup.sh
sudo ./spaghetti-watcher-setup.sh install
sudo nano /opt/spaghetti-watcher/spaghetti-watcher.env
sudo systemctl start spaghetti-watcher
```

## Management

```bash
# Status
sudo systemctl status mediamtx

# Logs
sudo journalctl -u mediamtx -f

# Camera settings
sudo nano /opt/mediamtx/start-cam.sh
sudo systemctl restart mediamtx

# MediaMTX config
sudo nano /opt/mediamtx/mediamtx.yml
sudo systemctl restart mediamtx
```

## Tuning

### Focus (Camera Module v3 only)

Edit `/opt/mediamtx/start-cam.sh` and change `--lens-position`:

| Value | Distance |
|-------|----------|
| 2.0 | ~50cm |
| 2.5 | ~40cm |
| 3.0 | ~33cm (default) |
| 3.5 | ~28cm |
| 4.0 | ~25cm |

### Image quality

Edit `/opt/mediamtx/start-cam.sh`:

```bash
--brightness 0.05    # -1.0 to 1.0 (0 = normal)
--contrast 1.15      # 0.0 to 2.0 (1.0 = normal)
--saturation 0.85    # 0.0 to 2.0 (1.0 = normal)
--sharpness 2.0      # 0.0 to 16.0 (1.0 = normal)
--awb tungsten       # auto, incandescent, tungsten, fluorescent, indoor, outdoor
--metering centre    # centre, spot, average, matrix
```

## Uninstall

```bash
sudo ./uninstall.sh
```

## What the setup script configures

- MediaMTX v1.13.1 as RTSP server
- `rpicam-vid` → `ffmpeg` → MediaMTX pipeline (avoids /dev/shm issues)
- `/dev/shm` limited to 256MB (prevents RAM exhaustion)
- SHM watchdog service (cleans /dev/shm if >80% full)
- 256MB swap file (prevents OOM kills)
- SSH keepalive (prevents disconnects)
- 6-hour reboot cronjob (stability)
- Systemd services with auto-restart

## Recommended 3D printed camera mounts (BambuLab P1S)

- [Piet 3D Corner Mount](https://makerworld.com/en/models/167238) – Pi Zero 2 + Pi Cam v2
- [GeekHo.me Mount](https://makerworld.com/en/models/694503) – Camera Module 3 (Standard + Wide)
- [Ordanicu Industries](https://makerworld.com/en/models/1869148) – Camera Module 3, various angles

> Print mounts in PETG or ABS – PLA may soften inside the P1S enclosure!

## License

MIT
