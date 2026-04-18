#!/bin/bash
# ============================================================
# wazuh_agent_deploy.sh
# Installiert und registriert einen Wazuh Agent auf Debian/Ubuntu
#
# Verwendung:
#   bash wazuh_agent_deploy.sh [OPTIONEN]
#
# Optionen:
#   -m, --manager-ip IP     IP-Adresse des Wazuh Managers
#   -n, --name NAME         Name des Agents (Standard: Hostname)
#   -v, --version VERSION   Wazuh Version (Standard: 4.14.3)
#   --help                  Diese Hilfe anzeigen
#
# Umgebungsvariablen (alternativ zu Optionen):
#   WAZUH_MANAGER_IP        IP-Adresse des Wazuh Managers
#   WAZUH_AGENT_NAME        Name des Agents
#   WAZUH_VERSION           Wazuh Version
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
WAZUH_MANAGER_IP="${WAZUH_MANAGER_IP:-}"
WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME:-}"
WAZUH_VERSION="${WAZUH_VERSION:-}"

# ── Argumente parsen ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--manager-ip)
      WAZUH_MANAGER_IP="$2"; shift 2 ;;
    -n|--name)
      WAZUH_AGENT_NAME="$2"; shift 2 ;;
    -v|--version)
      WAZUH_VERSION="$2"; shift 2 ;;
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
for cmd in curl systemctl; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Benötigtes Programm nicht gefunden: $cmd"
  fi
done

# ── Header ───────────────────────────────────────────────────
echo ""
echo "============================================"
echo "   Wazuh Agent Installer"
echo "============================================"
echo ""

# ── Interaktive Abfragen (falls Parameter fehlen) ────────────

# Manager IP
if [ -z "$WAZUH_MANAGER_IP" ]; then
  prompt "Wazuh Manager IP-Adresse eingeben:"
  read -rp "  > " WAZUH_MANAGER_IP
fi
if [ -z "$WAZUH_MANAGER_IP" ]; then
  error "Manager IP darf nicht leer sein."
fi

# Agent Name
if [ -z "$WAZUH_AGENT_NAME" ]; then
  DEFAULT_NAME=$(hostname)
  prompt "Agent Name eingeben [Standard: $DEFAULT_NAME]:"
  read -rp "  > " WAZUH_AGENT_NAME
  WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME:-$DEFAULT_NAME}"
fi

# Wazuh Version
if [ -z "$WAZUH_VERSION" ]; then
  prompt "Wazuh Version eingeben [Standard: 4.14.3]:"
  read -rp "  > " WAZUH_VERSION
  WAZUH_VERSION="${WAZUH_VERSION:-4.14.3}"
fi

# ── Zusammenfassung ──────────────────────────────────────────
echo ""
echo "--------------------------------------------"
echo "  Manager IP:   $WAZUH_MANAGER_IP"
echo "  Agent Name:   $WAZUH_AGENT_NAME"
echo "  Version:      $WAZUH_VERSION"
echo "--------------------------------------------"
prompt "Fortfahren? [j/N]:"
read -rp "  > " CONFIRM
if [[ ! "$CONFIRM" =~ ^[jJ]$ ]]; then
  echo "Abgebrochen."
  exit 0
fi
echo ""

# ── Architektur prüfen ───────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_LABEL="amd64" ;;
  aarch64) ARCH_LABEL="arm64" ;;
  *)       error "Nicht unterstützte Architektur: $ARCH" ;;
esac
info "Architektur: $ARCH_LABEL"

# ── Wazuh Repository einrichten ──────────────────────────────
info "Richte Wazuh Repository ein..."

curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
  | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  > /etc/apt/sources.list.d/wazuh.list

apt-get update -qq
info "Repository eingerichtet"

# ── Wazuh Agent installieren ─────────────────────────────────
info "Installiere Wazuh Agent v${WAZUH_VERSION}..."
WAZUH_MANAGER="$WAZUH_MANAGER_IP" \
WAZUH_AGENT_NAME="$WAZUH_AGENT_NAME" \
  apt-get install -y wazuh-agent="${WAZUH_VERSION}-1" 2>/dev/null \
  || apt-get install -y wazuh-agent 2>/dev/null \
  || error "Installation fehlgeschlagen. Prüfe die Paketquellen."

info "Wazuh Agent installiert"

# ── Agent konfigurieren ──────────────────────────────────────
info "Konfiguriere Agent..."
OSSEC_CONF="/var/ossec/etc/ossec.conf"

if [ -f "$OSSEC_CONF" ]; then
  sed -i "s|<address>.*</address>|<address>${WAZUH_MANAGER_IP}</address>|g" "$OSSEC_CONF"
  info "Manager IP in ossec.conf gesetzt: $WAZUH_MANAGER_IP"
else
  error "ossec.conf nicht gefunden unter $OSSEC_CONF"
fi

sed -i "s|<agent_name>.*</agent_name>|<agent_name>${WAZUH_AGENT_NAME}</agent_name>|g" "$OSSEC_CONF" 2>/dev/null || true

# ── Service aktivieren ───────────────────────────────────────
systemctl daemon-reload
systemctl enable --now wazuh-agent
info "Wazuh Agent Service gestartet"

# ── Verifikation ─────────────────────────────────────────────
sleep 3
if systemctl is-active --quiet wazuh-agent; then
  echo ""
  echo -e "${GREEN}[FERTIG]${NC} Wazuh Agent erfolgreich installiert und gestartet"
  echo ""
  echo "  Status prüfen:    systemctl status wazuh-agent"
  echo "  Logs prüfen:      tail -f /var/ossec/logs/ossec.log"
  echo ""
  warning "Hinweis: Der Agent muss im Wazuh Manager unter"
  warning "Agents → Pending manuell genehmigt werden."
else
  error "Wazuh Agent konnte nicht gestartet werden.\n         Prüfe: journalctl -u wazuh-agent -n 20"
fi
