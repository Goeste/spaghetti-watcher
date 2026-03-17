#!/bin/bash
# =============================================================================
# bambicam – Deinstallation
# =============================================================================

set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

[ "$EUID" -ne 0 ] && echo -e "${RED}Bitte als root: sudo ./uninstall.sh${NC}" && exit 1

echo -e "${RED}bambicam komplett deinstallieren?${NC}"
read -p "Fortfahren? (j/N) " CONFIRM
[[ ! "$CONFIRM" =~ ^[jJyY]$ ]] && exit 0

echo "[INFO] Stoppe Services..."
systemctl stop mediamtx shm-watchdog 2>/dev/null || true
systemctl disable mediamtx shm-watchdog 2>/dev/null || true

echo "[INFO] Entferne Service-Dateien..."
rm -f /etc/systemd/system/mediamtx.service
rm -f /etc/systemd/system/shm-watchdog.service
systemctl daemon-reload

echo "[INFO] Beende Prozesse..."
killall mediamtx rpicam-vid 2>/dev/null || true

echo "[INFO] Entferne Installation..."
rm -rf /opt/mediamtx
rm -rf /dev/shm/mediamtx-rpicamera-*

echo "[INFO] Entferne Reboot-Cronjob..."
crontab -l 2>/dev/null | grep -v "/sbin/reboot" | crontab - 2>/dev/null || true

echo ""
echo -e "${GREEN}bambicam deinstalliert.${NC}"
echo ""
echo "Nicht entfernt (manuell aufräumen falls gewünscht):"
echo "  - Swap:       /swapfile (in /etc/fstab)"
echo "  - SSH:        ClientAliveInterval (in /etc/ssh/sshd_config)"
echo "  - /dev/shm:   fstab Eintrag"
