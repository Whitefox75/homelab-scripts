#!/bin/bash
# ============================================================
# node_exporter_install.sh
# Installiert Prometheus node_exporter auf Debian/Ubuntu
#
# Verwendung:
#   bash node_exporter_install.sh [OPTIONEN]
#
# Optionen:
#   -v, --version VERSION   Spezifische Version erzwingen
#   --help                  Diese Hilfe anzeigen
#
# Umgebungsvariablen (alternativ zu Optionen):
#   NODE_EXPORTER_VERSION   Spezifische Version erzwingen
# ============================================================

set -e

# ── Farben ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}[*]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[FEHLER]${NC} $1"; exit 1; }
prompt()  { echo -e "${CYAN}[?]${NC} $1"; }

# ── Hilfe ────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
  exit 0
}

# ── Standardwerte ────────────────────────────────────────────
VERSION="${NODE_EXPORTER_VERSION:-}"

# ── Argumente parsen ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)
      VERSION="$2"; shift 2 ;;
    --help)
      usage ;;
    *)
      error "Unbekanntes Argument: $1 — Nutze --help für Hilfe." ;;
  esac
done

# ── Root-Prüfung ─────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  error "Dieses Skript muss als root ausgeführt werden (sudo bash $0)"
fi

# ── Abhängigkeiten prüfen ────────────────────────────────────
for cmd in curl wget tar systemctl; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Benötigtes Programm nicht gefunden: $cmd"
  fi
done

# ── Header ───────────────────────────────────────────────────
echo ""
echo "============================================"
echo "   node_exporter Installer"
echo "============================================"
echo ""

# ── Version ermitteln ────────────────────────────────────────
if [ -z "$VERSION" ]; then
  info "Ermittle aktuelle node_exporter Version von GitHub..."
  LATEST=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest \
    | grep '"tag_name"' \
    | sed 's/.*"v\([^"]*\)".*/\1/')
  if [ -z "$LATEST" ]; then
    error "Version konnte nicht ermittelt werden. Prüfe die Internetverbindung."
  fi
  prompt "Version eingeben [Standard: $LATEST (aktuell)]:"
  read -rp "  > " VERSION
  VERSION="${VERSION:-$LATEST}"
fi

# ── Architektur prüfen ───────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_LABEL="amd64" ;;
  aarch64) ARCH_LABEL="arm64" ;;
  *)       error "Nicht unterstützte Architektur: $ARCH" ;;
esac

# ── Zusammenfassung ──────────────────────────────────────────
echo ""
echo "--------------------------------------------"
echo "  Version:       $VERSION"
echo "  Architektur:   $ARCH_LABEL"
echo "  Install-Pfad:  /usr/local/bin/node_exporter"
echo "  Port:          9100"
echo "--------------------------------------------"
prompt "Fortfahren? [j/N]:"
read -rp "  > " CONFIRM
if [[ ! "$CONFIRM" =~ ^[jJ]$ ]]; then
  echo "Abgebrochen."
  exit 0
fi
echo ""

# ── Bereits installiert? ─────────────────────────────────────
if command -v node_exporter &>/dev/null; then
  CURRENT_VERSION=$(node_exporter --version 2>&1 | head -1 | awk '{print $3}' || echo "unbekannt")
  warning "node_exporter ist bereits installiert (Version: $CURRENT_VERSION)"
  prompt "Neuinstallation / Aktualisierung auf v${VERSION} fortsetzen? [j/N]:"
  read -rp "  > " REINSTALL
  if [[ ! "$REINSTALL" =~ ^[jJ]$ ]]; then
    echo "Abgebrochen."
    exit 0
  fi
fi

# ── User anlegen ─────────────────────────────────────────────
if id "node_exporter" &>/dev/null; then
  warning "User node_exporter existiert bereits, überspringe..."
else
  useradd --no-create-home --shell /bin/false node_exporter
  info "User node_exporter angelegt"
fi

# ── Download & Installation ──────────────────────────────────
FILENAME="node_exporter-${VERSION}.linux-${ARCH_LABEL}"
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${FILENAME}.tar.gz"

info "Lade node_exporter v${VERSION} herunter..."
cd /tmp
wget -q "$DOWNLOAD_URL" || error "Download fehlgeschlagen: $DOWNLOAD_URL"
tar xf "${FILENAME}.tar.gz"
cp "${FILENAME}/node_exporter" /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter
info "Binary installiert nach /usr/local/bin/node_exporter"

# ── systemd Unit-File ────────────────────────────────────────
info "Erstelle systemd Service..."
cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# ── Service aktivieren ───────────────────────────────────────
systemctl daemon-reload
systemctl enable --now node_exporter
info "Service gestartet und für Autostart aktiviert"

# ── Verifikation ─────────────────────────────────────────────
sleep 2
if systemctl is-active --quiet node_exporter; then
  echo ""
  echo -e "${GREEN}[FERTIG]${NC} node_exporter v${VERSION} erfolgreich installiert"
  echo ""
  echo "  Metriken prüfen: curl http://localhost:9100/metrics | head -20"
  echo "  Status prüfen:   systemctl status node_exporter"
else
  error "node_exporter konnte nicht gestartet werden.\n         Prüfe: journalctl -u node_exporter -n 20"
fi

# ── Aufräumen ────────────────────────────────────────────────
rm -rf /tmp/${FILENAME}*
