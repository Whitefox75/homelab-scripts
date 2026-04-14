#!/bin/bash
# ============================================================
# wazuh_agent_deploy.sh
# Installiert und registriert einen Wazuh Agent auf Debian/Ubuntu
# Verwendung: bash wazuh_agent_deploy.sh
# Umgebungsvariablen (optional):
#   WAZUH_MANAGER_IP    — IP-Adresse des Wazuh Managers
#   WAZUH_AGENT_NAME    — Name des Agents (Standard: Hostname)
#   WAZUH_VERSION       — Wazuh Version (Standard: 4.x aktuell)
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

# ── Eingaben abfragen ────────────────────────────────────────
echo ""
echo "============================================"
echo "   Wazuh Agent Installer"
echo "============================================"
echo ""

# Manager IP
WAZUH_MANAGER_IP="${WAZUH_MANAGER_IP:-}"
if [ -z "$WAZUH_MANAGER_IP" ]; then
  prompt "Wazuh Manager IP-Adresse eingeben:"
  read -rp "  > " WAZUH_MANAGER_IP
fi
if [ -z "$WAZUH_MANAGER_IP" ]; then
  error "Manager IP darf nicht leer sein."
fi

# Agent Name
WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME:-}"
if [ -z "$WAZUH_AGENT_NAME" ]; then
  DEFAULT_NAME=$(hostname)
  prompt "Agent Name eingeben [Standard: $DEFAULT_NAME]:"
  read -rp "  > " WAZUH_AGENT_NAME
  WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME:-$DEFAULT_NAME}"
fi

# Wazuh Version
WAZUH_VERSION="${WAZUH_VERSION:-}"
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

# GPG Key importieren
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
  | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg

# Repository hinzufügen
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

# Manager IP in Konfiguration setzen
if [ -f "$OSSEC_CONF" ]; then
  sed -i "s|<address>.*</address>|<address>${WAZUH_MANAGER_IP}</address>|g" "$OSSEC_CONF"
  info "Manager IP in ossec.conf gesetzt: $WAZUH_MANAGER_IP"
else
  error "ossec.conf nicht gefunden unter $OSSEC_CONF"
fi

# Agent Name setzen
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
