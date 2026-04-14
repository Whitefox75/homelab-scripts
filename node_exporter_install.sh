#!/bin/bash
# ============================================================
# node_exporter_install.sh
# Installiert Prometheus node_exporter auf Debian/Ubuntu
# Verwendung: bash node_exporter_install.sh
# Umgebungsvariablen (optional):
#   NODE_EXPORTER_VERSION  — spezifische Version erzwingen
# ============================================================

set -e

# ── Farben ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[*]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[FEHLER]${NC} $1"; exit 1; }

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

# ── Version ermitteln ────────────────────────────────────────
VERSION="${NODE_EXPORTER_VERSION:-}"
if [ -z "$VERSION" ]; then
  info "Ermittle aktuelle node_exporter Version von GitHub..."
  VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest \
    | grep '"tag_name"' \
    | sed 's/.*"v\([^"]*\)".*/\1/')
  if [ -z "$VERSION" ]; then
    error "Version konnte nicht ermittelt werden. Prüfe die Internetverbindung."
  fi
fi
info "Version: $VERSION"

# ── Architektur prüfen ───────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_LABEL="amd64" ;;
  aarch64) ARCH_LABEL="arm64" ;;
  *)       error "Nicht unterstützte Architektur: $ARCH" ;;
esac
info "Architektur: $ARCH_LABEL"

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

info "Lade node_exporter herunter..."
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
  info "node_exporter läuft auf Port 9100"
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
