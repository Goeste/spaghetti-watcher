#!/bin/bash
# =============================================================================
# bambicam Spaghetti-Wächter – All-in-One Setup
# =============================================================================
#
# Runs on a SEPARATE server (not the Pi!), monitors the camera stream
# via Obico ML API and sends Pushsafer notifications / pauses prints.
#
#   sudo ./spaghetti-watcher-setup.sh install
#   sudo nano /opt/spaghetti-watcher/spaghetti-watcher.env
#   sudo systemctl start spaghetti-watcher
#
#   sudo ./spaghetti-watcher-setup.sh status
#   sudo ./spaghetti-watcher-setup.sh uninstall
#
# =============================================================================

INSTALL_DIR="/opt/spaghetti-watcher"
SERVICE_NAME="spaghetti-watcher"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
do_install() {
    [ "$EUID" -ne 0 ] && error "Bitte als root: sudo $0 install"

    info "Installiere Abhängigkeiten..."
    apt-get update -qq
    apt-get install -y -qq ffmpeg curl mosquitto-clients bc python3

    mkdir -p "$INSTALL_DIR"

    # --- Watcher Script ---
    info "Erstelle Watcher-Script..."
    cat > "${INSTALL_DIR}/spaghetti-watcher.sh" << 'WATCHER'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/spaghetti-watcher.env"
[ ! -f "$ENV_FILE" ] && echo "FEHLER: $ENV_FILE nicht gefunden!" && exit 1
source "$ENV_FILE"

RTSP_URL="${RTSP_URL:-rtsp://localhost:8554/cam}"
OBICO_ML_URL="${OBICO_ML_URL:-http://localhost:3333}"
PUSHSAFER_KEY="${PUSHSAFER_KEY:-}"
PUSHSAFER_DEVICE="${PUSHSAFER_DEVICE:-a}"
BAMBU_IP="${BAMBU_IP:-}"
BAMBU_ACCESS_CODE="${BAMBU_ACCESS_CODE:-}"
BAMBU_SERIAL="${BAMBU_SERIAL:-}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
WARN_THRESHOLD="${WARN_THRESHOLD:-0.40}"
PAUSE_THRESHOLD="${PAUSE_THRESHOLD:-0.65}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-/tmp/spaghetti-watcher}"
LOG_FILE="${LOG_FILE:-/var/log/spaghetti-watcher.log}"
COOLDOWN="${COOLDOWN:-300}"

LAST_ALERT_TIME=0
PAUSED=false
mkdir -p "$SNAPSHOT_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

send_pushsafer() {
    local TITLE="$1" MESSAGE="$2" ICON="${3:-12}" SOUND="${4:-10}" PRIORITY="${5:-2}" IMAGE_PATH="${6:-}"
    [ -z "$PUSHSAFER_KEY" ] && log "WARNUNG: Kein Pushsafer Key" && return
    local CURL_ARGS=(-s -X POST "https://www.pushsafer.com/api"
        -F "k=${PUSHSAFER_KEY}" -F "d=${PUSHSAFER_DEVICE}"
        -F "t=${TITLE}" -F "m=${MESSAGE}" -F "i=${ICON}"
        -F "s=${SOUND}" -F "v=3" -F "pr=${PRIORITY}" -F "c=#FF0000")
    if [ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ]; then
        CURL_ARGS+=(-F "p=data:image/jpeg;base64,$(base64 -w 0 "$IMAGE_PATH")")
    fi
    local RESP=$(curl "${CURL_ARGS[@]}" 2>/dev/null)
    echo "$RESP" | grep -q '"success":1' && log "Pushsafer: gesendet" || log "Pushsafer FEHLER: $RESP"
}

pause_print() {
    [ -z "$BAMBU_IP" ] || [ -z "$BAMBU_ACCESS_CODE" ] || [ -z "$BAMBU_SERIAL" ] && log "MQTT nicht konfiguriert" && return 1
    log "Pausiere Druck auf ${BAMBU_IP}..."
    mosquitto_pub -h "$BAMBU_IP" -p 8883 -u "bblp" -P "$BAMBU_ACCESS_CODE" \
        -t "device/$BAMBU_SERIAL/request" --cafile /dev/null --insecure \
        -m '{"print":{"command":"pause","sequence_id":"0"}}' 2>/dev/null
    [ $? -eq 0 ] && log "Druck pausiert!" && PAUSED=true || log "FEHLER: Pause fehlgeschlagen"
}

take_snapshot() {
    local S="${SNAPSHOT_DIR}/snapshot_$(date +%s).jpg"
    ffmpeg -rtsp_transport tcp -i "$RTSP_URL" -frames:v 1 -q:v 2 -y "$S" 2>/dev/null
    [ -f "$S" ] && [ -s "$S" ] && echo "$S" && return 0
    rm -f "$S" 2>/dev/null; return 1
}

check_spaghetti() {
    local RESP=$(curl -s -X POST "${OBICO_ML_URL}/p/" -F "img=@${1}" 2>/dev/null)
    [ -z "$RESP" ] && log "ML API nicht erreichbar" && return 1
    echo "$RESP" | python3 -c "
import sys,json
try:
 d=json.load(sys.stdin)
 c=d.get('p',d.get('confidence',0)) if isinstance(d,dict) else (max(x.get('p',0) for x in d) if isinstance(d,list) and d else 0)
 print(f'{c:.4f}')
except: print('0.0000')" 2>/dev/null
}

log "===== Spaghetti-Wächter gestartet ====="
log "Stream: $RTSP_URL | ML API: $OBICO_ML_URL | Intervall: ${CHECK_INTERVAL}s"
log "Schwellen: Warnung=${WARN_THRESHOLD} Pause=${PAUSE_THRESHOLD}"

while true; do
    SNAP=$(take_snapshot)
    if [ $? -ne 0 ]; then log "Kein Snapshot – Stream offline?"; sleep "$CHECK_INTERVAL"; continue; fi
    CONFIDENCE=$(check_spaghetti "$SNAP")
    if [ $? -ne 0 ]; then rm -f "$SNAP" 2>/dev/null; sleep "$CHECK_INTERVAL"; continue; fi

    NOW=$(date +%s); TIME_SINCE=$(( NOW - LAST_ALERT_TIME ))

    if (( $(echo "$CONFIDENCE >= $PAUSE_THRESHOLD" | bc -l) )); then
        log "KRITISCH: Spaghetti! (${CONFIDENCE})"
        if [ "$PAUSED" = false ]; then
            pause_print
            send_pushsafer "🚨 SPAGHETTI!" "Konfidenz: ${CONFIDENCE}%0ADruck pausiert!" "12" "10" "2" "$SNAP"
            LAST_ALERT_TIME=$NOW
        fi
    elif (( $(echo "$CONFIDENCE >= $WARN_THRESHOLD" | bc -l) )); then
        log "WARNUNG: Möglicher Fehler (${CONFIDENCE})"
        [ $TIME_SINCE -ge $COOLDOWN ] && send_pushsafer "⚠️ Druckfehler?" "Konfidenz: ${CONFIDENCE}%0ADruck läuft weiter." "48" "1" "1" "$SNAP" && LAST_ALERT_TIME=$NOW
    else
        log "OK (${CONFIDENCE})"
        [ "$PAUSED" = true ] && (( $(echo "$CONFIDENCE < $WARN_THRESHOLD" | bc -l) )) && PAUSED=false && log "Pause zurückgesetzt"
    fi

    rm -f "$SNAP" 2>/dev/null
    find "$SNAPSHOT_DIR" -name "snapshot_*.jpg" -mmin +60 -delete 2>/dev/null
    sleep "$CHECK_INTERVAL"
done
WATCHER
    chmod +x "${INSTALL_DIR}/spaghetti-watcher.sh"

    # --- Config ---
    if [ ! -f "${INSTALL_DIR}/spaghetti-watcher.env" ]; then
        info "Erstelle Konfiguration..."
        cat > "${INSTALL_DIR}/spaghetti-watcher.env" << 'ENVCONF'
# bambicam Spaghetti-Wächter Konfiguration

# --- bambicam Stream ---
RTSP_URL=rtsp://BAMBICAM-IP:8554/cam

# --- Obico ML API ---
OBICO_ML_URL=http://localhost:3333

# --- Pushsafer (https://www.pushsafer.com/dashboard) ---
PUSHSAFER_KEY=DEIN_PUSHSAFER_KEY
PUSHSAFER_DEVICE=a

# --- BambuLab Drucker (Auto-Pause via MQTT) ---
BAMBU_IP=DRUCKER-IP
BAMBU_ACCESS_CODE=DEIN_ACCESS_CODE
BAMBU_SERIAL=DEINE_SERIENNUMMER

# --- Einstellungen ---
CHECK_INTERVAL=30
WARN_THRESHOLD=0.40
PAUSE_THRESHOLD=0.65
COOLDOWN=300
SNAPSHOT_DIR=/tmp/spaghetti-watcher
LOG_FILE=/var/log/spaghetti-watcher.log
ENVCONF
        warn "Config anpassen: sudo nano ${INSTALL_DIR}/spaghetti-watcher.env"
    fi

    # --- Systemd Service ---
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=bambicam Spaghetti-Wächter
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=${INSTALL_DIR}/spaghetti-watcher.sh
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"

    if grep -q "DEIN_PUSHSAFER_KEY" "${INSTALL_DIR}/spaghetti-watcher.env" 2>/dev/null; then
        warn "Bitte zuerst konfigurieren, dann starten:"
        warn "  sudo nano ${INSTALL_DIR}/spaghetti-watcher.env"
        warn "  sudo systemctl start ${SERVICE_NAME}"
    else
        systemctl start "${SERVICE_NAME}.service"
    fi

    echo ""
    echo -e "${GREEN}Spaghetti-Wächter installiert!${NC}"
    echo "  Konfig:  sudo nano ${INSTALL_DIR}/spaghetti-watcher.env"
    echo "  Start:   sudo systemctl start ${SERVICE_NAME}"
    echo "  Logs:    sudo journalctl -u ${SERVICE_NAME} -f"
}

# =============================================================================
do_uninstall() {
    [ "$EUID" -ne 0 ] && error "Bitte als root: sudo $0 uninstall"
    read -p "Deinstallieren? (j/N) " CONFIRM
    [[ ! "$CONFIRM" =~ ^[jJyY]$ ]] && exit 0
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    rm -f "${INSTALL_DIR}/spaghetti-watcher.sh"
    rm -rf /tmp/spaghetti-watcher
    echo -e "${GREEN}Deinstalliert. Config bleibt: ${INSTALL_DIR}/spaghetti-watcher.env${NC}"
}

# =============================================================================
do_status() {
    echo -e "${CYAN}=== Spaghetti-Wächter ===${NC}"
    systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null \
        && echo -e "  Service: ${GREEN}läuft${NC}" \
        || echo -e "  Service: ${RED}gestoppt${NC}"
    if [ -f "${INSTALL_DIR}/spaghetti-watcher.env" ]; then
        source "${INSTALL_DIR}/spaghetti-watcher.env"
        echo "  Stream:  ${RTSP_URL}"
        echo "  ML API:  ${OBICO_ML_URL}"
        curl -s "${OBICO_ML_URL}/hc/" > /dev/null 2>&1 \
            && echo -e "  ML API:  ${GREEN}erreichbar${NC}" \
            || echo -e "  ML API:  ${RED}nicht erreichbar${NC}"
    fi
    echo "  Logs:"
    journalctl -u "${SERVICE_NAME}" -n 5 --no-pager 2>/dev/null | sed 's/^/    /'
}

# =============================================================================
case "${1:-}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    status)    do_status ;;
    *) echo "Verwendung: $0 {install|uninstall|status}" ;;
esac
