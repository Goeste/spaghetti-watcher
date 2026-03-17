# Spaghetti Watcher

AI-based 3D print failure detection using [Obico ML API](https://github.com/TheSpaghettiDetective/obico-server). Monitors the bambicam RTSP stream, sends notifications via [Pushsafer](https://www.pushsafer.com/) and auto-pauses BambuLab prints via MQTT.

> **Important:** Run this on a separate server, NOT on the Pi Zero 2 W!

## Prerequisites

- [Obico ML API](https://github.com/TheSpaghettiDetective/obico-server) running (Docker)
- bambicam RTSP stream accessible
- [Pushsafer](https://www.pushsafer.com/) account and Private Key
- BambuLab printer LAN access code and serial number

## Setup

```bash
chmod +x spaghetti-watcher-setup.sh
sudo ./spaghetti-watcher-setup.sh install
sudo nano /opt/spaghetti-watcher/spaghetti-watcher.env
sudo systemctl start spaghetti-watcher
```

## Configuration

Edit `/opt/spaghetti-watcher/spaghetti-watcher.env`:

| Variable | Description | Default |
|----------|------------|---------|
| `RTSP_URL` | bambicam stream URL | `rtsp://BAMBICAM-IP:8554/cam` |
| `OBICO_ML_URL` | Obico ML API URL | `http://localhost:3333` |
| `PUSHSAFER_KEY` | Your Pushsafer private key | – |
| `PUSHSAFER_DEVICE` | Device ID or `a` for all | `a` |
| `BAMBU_IP` | BambuLab printer IP | – |
| `BAMBU_ACCESS_CODE` | LAN access code | – |
| `BAMBU_SERIAL` | Printer serial number | – |
| `CHECK_INTERVAL` | Seconds between checks | `30` |
| `WARN_THRESHOLD` | Confidence for warning (0-1) | `0.40` |
| `PAUSE_THRESHOLD` | Confidence for auto-pause (0-1) | `0.65` |
| `COOLDOWN` | Seconds between warnings | `300` |

## Commands

```bash
sudo ./spaghetti-watcher-setup.sh status     # Check status
sudo systemctl stop spaghetti-watcher        # Stop
sudo systemctl restart spaghetti-watcher     # Restart
sudo journalctl -u spaghetti-watcher -f      # Live logs
sudo ./spaghetti-watcher-setup.sh uninstall  # Remove
```
