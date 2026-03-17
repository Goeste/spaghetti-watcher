#!/bin/bash
# =============================================================================
# bambicam – RTSP Kamera-Stream für Raspberry Pi Zero 2 W
# Optimiert für BambuLab P1S mit Obico Spaghetti-Detection
# =============================================================================
#
# Stream erreichbar unter: rtsp://<PI-IP>:8554/cam
#
# Verwendung:
#   chmod +x setup.sh
#   sudo ./setup.sh
#
# Non-interaktiv (z.B. in Scripts):
#   sudo CAMERA_MODULE=v3wide MOUNT_ORIENTATION=normal ./setup.sh
#
# =============================================================================

set -e

MEDIAMTX_VERSION="v1.13.1"
INSTALL_DIR="/opt/mediamtx"
STREAM_PATH="cam"

# --- Farben ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Root-Check ---
[ "$EUID" -ne 0 ] && error "Bitte als root: sudo ./setup.sh"

echo -e "${CYAN}"
echo "============================================================================="
echo "  bambicam – Raspberry Pi Zero 2 W Kamera Setup"
echo "  Optimiert für BambuLab P1S + Obico Spaghetti-Detection"
echo "============================================================================="
echo -e "${NC}"

# =============================================================================
# INTERAKTIVE ABFRAGEN (falls nicht per Env gesetzt)
# =============================================================================

# --- Kamera-Modul ---
if [ -z "$CAMERA_MODULE" ]; then
    echo -e "${BOLD}Welches Kamera-Modul nutzt du?${NC}"
    echo ""
    echo "  1) Camera Module v3 Wide  (IMX708, 12MP, AF, 120° FOV) ← empfohlen"
    echo "  2) Camera Module v3       (IMX708, 12MP, AF, 66° FOV)"
    echo "  3) Camera Module v2       (IMX219, 8MP, Fixfokus)"
    echo "  4) Arducam IMX219 Wide    (8MP, Fixfokus, Weitwinkel)"
    echo "  5) Camera Module v1       (OV5647, 5MP, Fixfokus)"
    echo ""
    read -p "  Auswahl [1-5]: " CAM_CHOICE
    case "$CAM_CHOICE" in
        1) CAMERA_MODULE="v3wide" ;;
        2) CAMERA_MODULE="v3" ;;
        3) CAMERA_MODULE="v2" ;;
        4) CAMERA_MODULE="arducam" ;;
        5) CAMERA_MODULE="v1" ;;
        *) CAMERA_MODULE="v3wide"; warn "Ungültige Auswahl, nutze v3wide" ;;
    esac
    echo ""
fi

# --- Montage-Orientierung ---
if [ -z "$MOUNT_ORIENTATION" ]; then
    echo -e "${BOLD}Wie ist die Kamera montiert?${NC}"
    echo ""
    echo "  1) Normal   – Kamera aufrecht, Ribbon-Kabel nach unten"
    echo "  2) Gedreht  – Kamera 180° kopfüber (typisch bei Corner-Mounts)"
    echo ""
    read -p "  Auswahl [1-2]: " ORIENT_CHOICE
    case "$ORIENT_CHOICE" in
        1) MOUNT_ORIENTATION="normal" ;;
        2) MOUNT_ORIENTATION="flipped" ;;
        *) MOUNT_ORIENTATION="normal"; warn "Ungültige Auswahl, nutze normal" ;;
    esac
    echo ""
fi

# =============================================================================
# KAMERA-PROFILE
# =============================================================================

# Pi Zero 2 W optimiert: 1280x720, max 10fps, moderate Bitrate
case "$CAMERA_MODULE" in
    v3|v3wide)
        WIDTH=1280; HEIGHT=720; FPS=10; BITRATE=2500000
        AF_OPTS="--autofocus-mode manual --lens-position 3.0"
        ;;
    v2|arducam)
        WIDTH=1280; HEIGHT=720; FPS=10; BITRATE=2500000
        AF_OPTS=""
        ;;
    v1)
        WIDTH=1280; HEIGHT=720; FPS=8; BITRATE=2000000
        AF_OPTS=""
        ;;
    *) error "Unbekanntes Kamera-Modul: $CAMERA_MODULE" ;;
esac

case "$MOUNT_ORIENTATION" in
    flipped) VFLIP="--vflip --hflip" ;;
    normal)  VFLIP="" ;;
    *) error "Unbekannte Orientierung: $MOUNT_ORIENTATION" ;;
esac

info "Kamera:   $CAMERA_MODULE"
info "Montage:  $MOUNT_ORIENTATION"
info "Stream:   ${WIDTH}x${HEIGHT} @ ${FPS}fps @ $(( BITRATE / 1000 ))kbps"
echo ""

# =============================================================================
# ALTE INSTALLATION ENTFERNEN
# =============================================================================
info "Entferne bestehende Installation..."

if systemctl is-active --quiet mediamtx 2>/dev/null; then
    systemctl stop mediamtx
fi
if systemctl is-enabled --quiet mediamtx 2>/dev/null; then
    systemctl disable mediamtx
fi
rm -f /etc/systemd/system/mediamtx.service
systemctl daemon-reload 2>/dev/null

# Laufende Prozesse beenden
killall mediamtx 2>/dev/null || true
killall rpicam-vid 2>/dev/null || true
sleep 1

# Altes Verzeichnis entfernen
rm -rf "$INSTALL_DIR"

# /dev/shm aufräumen
rm -rf /dev/shm/mediamtx-rpicamera-* 2>/dev/null

# =============================================================================
# ABHÄNGIGKEITEN
# =============================================================================
info "Installiere Abhängigkeiten..."
apt-get update -qq
apt-get install -y -qq libfreetype6 curl ffmpeg

# =============================================================================
# KAMERA TESTEN
# =============================================================================
info "Teste Kamera..."
if rpicam-hello --timeout 1000 --nopreview 2>/dev/null; then
    info "Kamera erkannt"
else
    warn "Kamera-Test fehlgeschlagen – prüfe Ribbon-Kabel"
fi

# =============================================================================
# MEDIAMTX INSTALLIEREN
# =============================================================================
info "Installiere MediaMTX ${MEDIAMTX_VERSION}..."

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) MEDIAMTX_ARCH="linux_arm64" ;;
    armv7l)  MEDIAMTX_ARCH="linux_armv7" ;;
    armv6l)  MEDIAMTX_ARCH="linux_armv6" ;;
    *) error "Unbekannte Architektur: $ARCH" ;;
esac

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
curl -sL -o mediamtx.tar.gz "https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/mediamtx_${MEDIAMTX_VERSION}_${MEDIAMTX_ARCH}.tar.gz"

if ! file mediamtx.tar.gz | grep -q "gzip"; then
    error "Download fehlgeschlagen"
fi

tar xzf mediamtx.tar.gz
mkdir -p "$INSTALL_DIR"
cp mediamtx "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/mediamtx"
rm -rf "$TMP_DIR"

# =============================================================================
# KAMERA-START-SCRIPT
# =============================================================================
info "Erstelle Kamera-Script..."

cat > "$INSTALL_DIR/start-cam.sh" << CAMSCRIPT
#!/bin/bash
rpicam-vid \\
  --width ${WIDTH} --height ${HEIGHT} --framerate ${FPS} \\
  --bitrate ${BITRATE} --profile main --level 4.1 \\
  --timeout 0 --nopreview --inline \\
  --brightness 0.05 --contrast 1.15 \\
  --saturation 0.85 --sharpness 2.0 \\
  --awb tungsten --metering centre \\
  --denoise off \\
  ${AF_OPTS} \\
  ${VFLIP} \\
  --codec h264 -o - \\
  | ffmpeg -fflags +genpts -i - -c copy -f rtsp rtsp://localhost:8554/${STREAM_PATH}
CAMSCRIPT
chmod +x "$INSTALL_DIR/start-cam.sh"

# =============================================================================
# MEDIAMTX KONFIGURATION
# =============================================================================
info "Erstelle MediaMTX Konfiguration..."

cat > "$INSTALL_DIR/mediamtx.yml" << EOF
# bambicam – MediaMTX Konfiguration
# Kamera: ${CAMERA_MODULE} | Montage: ${MOUNT_ORIENTATION}

logLevel: info
logDestinations: [stdout]

rtsp: true
rtspAddress: :8554
rtspTransports: [udp, tcp]

webrtc: no
hls: no
rtmp: no
srt: no

paths:
  ${STREAM_PATH}:
    runOnInit: ${INSTALL_DIR}/start-cam.sh
    runOnInitRestart: yes
    sourceOnDemand: no
  all_others:
EOF

# =============================================================================
# /dev/shm KONFIGURIEREN
# =============================================================================
info "Konfiguriere /dev/shm..."

# fstab Eintrag setzen (256MB, nur einmal)
if ! grep -q "tmpfs /dev/shm" /etc/fstab; then
    echo "tmpfs /dev/shm tmpfs defaults,size=256M 0 0" >> /etc/fstab
fi
mount -o remount,size=256M /dev/shm 2>/dev/null || true

# =============================================================================
# SHM WATCHDOG
# =============================================================================
info "Erstelle SHM Watchdog..."

cat > "$INSTALL_DIR/shm-watchdog.sh" << 'WATCHDOG'
#!/bin/bash
while true; do
    USAGE=$(df /dev/shm --output=pcent | tail -1 | tr -d ' %')
    if [ "$USAGE" -ge 80 ]; then
        rm -rf /dev/shm/mediamtx-rpicamera-*
        systemctl restart mediamtx
        logger "shm-watchdog: /dev/shm bei ${USAGE}% – aufgeräumt"
    fi
    sleep 15
done
WATCHDOG
chmod +x "$INSTALL_DIR/shm-watchdog.sh"

cat > /etc/systemd/system/shm-watchdog.service << EOF
[Unit]
Description=SHM Watchdog für MediaMTX
After=mediamtx.service

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/shm-watchdog.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# SWAP KONFIGURIEREN
# =============================================================================
info "Konfiguriere Swap..."

if ! swapon --show | grep -q "/swapfile"; then
    if [ ! -f /swapfile ]; then
        fallocate -l 256M /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    swapon /swapfile 2>/dev/null || true
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
fi

# =============================================================================
# SSH KEEPALIVE
# =============================================================================
info "Konfiguriere SSH Keepalive..."

if ! grep -q "ClientAliveInterval" /etc/ssh/sshd_config; then
    echo "" >> /etc/ssh/sshd_config
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
    systemctl restart sshd 2>/dev/null || true
fi

# =============================================================================
# SYSTEMD SERVICES
# =============================================================================
info "Erstelle MediaMTX Service..."

cat > /etc/systemd/system/mediamtx.service << EOF
[Unit]
Description=bambicam – MediaMTX RTSP
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/mediamtx ${INSTALL_DIR}/mediamtx.yml
Restart=always
RestartSec=5
SupplementaryGroups=video

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mediamtx.service
systemctl enable shm-watchdog.service
systemctl start mediamtx.service
sleep 3
systemctl start shm-watchdog.service

# =============================================================================
# CRONJOB (6h Reboot)
# =============================================================================
info "Erstelle Reboot-Cronjob..."

if ! crontab -l 2>/dev/null | grep -q "/sbin/reboot"; then
    (crontab -l 2>/dev/null; echo "0 */6 * * * /sbin/reboot") | crontab -
fi

# =============================================================================
# ZUSAMMENFASSUNG
# =============================================================================
PI_IP=$(hostname -I | awk '{print $1}')

sleep 5

echo ""
echo -e "${CYAN}=============================================================================${NC}"
echo -e "${GREEN} bambicam installiert!${NC}"
echo -e "${CYAN}=============================================================================${NC}"
echo ""
echo "  Kamera:     ${CAMERA_MODULE} (${MOUNT_ORIENTATION})"
echo "  Auflösung:  ${WIDTH}x${HEIGHT} @ ${FPS}fps"
echo ""
echo "  RTSP:       rtsp://${PI_IP}:8554/${STREAM_PATH}"
echo ""
echo "  Test:       ffplay -rtsp_transport tcp rtsp://${PI_IP}:8554/${STREAM_PATH}"
echo ""
echo "  Status:     sudo systemctl status mediamtx"
echo "  Logs:       sudo journalctl -u mediamtx -f"
echo "  Konfig:     sudo nano ${INSTALL_DIR}/mediamtx.yml"
echo "  Kamera:     sudo nano ${INSTALL_DIR}/start-cam.sh"
echo ""
echo "  Reboot:     alle 6 Stunden (Cronjob)"
echo "  SHM:        Watchdog aktiv (räumt /dev/shm auf)"
echo "  Swap:       256 MB aktiv"
echo "  SSH:        Keepalive aktiv"
echo ""
echo -e "${CYAN}=============================================================================${NC}"

# Stream-Check
if journalctl -u mediamtx --no-pager -n 10 2>/dev/null | grep -q "is publishing"; then
    echo -e "  Stream: ${GREEN}AKTIV${NC}"
else
    warn "Stream noch nicht bereit – prüfe: sudo journalctl -u mediamtx -f"
fi
echo -e "${CYAN}=============================================================================${NC}"
