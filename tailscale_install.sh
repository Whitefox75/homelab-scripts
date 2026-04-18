#!/bin/bash
# ============================================================
# tailscale_install.sh
# Installiert und verbindet Tailscale auf Debian 12
#
# Verwendung:
#   bash tailscale_install.sh [OPTIONEN]
#
# Optionen:
#   -k, --auth-key KEY      Tailscale Auth-Key (tskey-auth-...)
#   -h, --hostname NAME     Hostname im Tailnet (Standard: Systemhostname)
#   -t, --tags TAGS         ACL-Tags (kommagetrennt, z.B. tag:server,tag:homelab)
#   -e, --exit-node         Diese VM als Exit-Node anbieten
#   -s, --ssh               Tailscale SSH aktivieren
#   --shields-up            Shields Up (nur ausgehende Verbindungen)
#   --help                  Diese Hilfe anzeigen
#
# Umgebungsvariablen (alternativ zu Optionen):
#   TS_AUTH_KEY             Tailscale Auth-Key
#   TS_HOSTNAME             Hostname im Tailnet
#   TS_TAGS                 ACL-Tags
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
AUTH_KEY="${TS_AUTH_KEY:-}"
TS_HOSTNAME="${TS_HOSTNAME:-}"
TAGS="${TS_TAGS:-}"
EXIT_NODE=false
ENABLE_SSH=false
SHIELDS_UP=false

# ── Argumente parsen ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--auth-key)
      AUTH_KEY="$2"; shift 2 ;;
    -h|--hostname)
      TS_HOSTNAME="$2"; shift 2 ;;
    -t|--tags)
      TAGS="$2"; shift 2 ;;
    -e|--exit-node)
      EXIT_NODE=true; shift ;;
    -s|--ssh)
      ENABLE_SSH=true; shift ;;
    --shields-up)
      SHIELDS_UP=true; shift ;;
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

# ── Interaktive Abfragen (falls Parameter fehlen) ────────────
echo ""
echo "============================================"
echo "   Tailscale Installer"
echo "============================================"
echo ""

# Auth-Key
if [ -z "$AUTH_KEY" ]; then
  prompt "Tailscale Auth-Key eingeben (tskey-auth-...):"
  prompt "  Erstellen unter: https://login.tailscale.com/admin/settings/keys"
  read -rsp "  > " AUTH_KEY
  echo ""
fi
if [ -z "$AUTH_KEY" ]; then
  error "Auth-Key darf nicht leer sein."
fi

# Hostname
if [ -z "$TS_HOSTNAME" ]; then
  DEFAULT_HOST=$(hostname)
  prompt "Hostname im Tailnet [Standard: $DEFAULT_HOST]:"
  read -rp "  > " TS_HOSTNAME
  TS_HOSTNAME="${TS_HOSTNAME:-$DEFAULT_HOST}"
fi

# Tags (optional)
if [ -z "$TAGS" ]; then
  prompt "ACL-Tags setzen? (kommagetrennt, z.B. tag:server,tag:homelab) [leer = keine Tags]:"
  read -rp "  > " TAGS
fi

# Exit-Node
if [ "$EXIT_NODE" = false ]; then
  prompt "Diese VM als Exit-Node anbieten? [j/N]:"
  read -rp "  > " EXIT_ANSWER
  [[ "$EXIT_ANSWER" =~ ^[jJ]$ ]] && EXIT_NODE=true
fi

# Tailscale SSH
if [ "$ENABLE_SSH" = false ]; then
  prompt "Tailscale SSH aktivieren? [j/N]:"
  read -rp "  > " SSH_ANSWER
  [[ "$SSH_ANSWER" =~ ^[jJ]$ ]] && ENABLE_SSH=true
fi

# ── Zusammenfassung ──────────────────────────────────────────
echo ""
echo "--------------------------------------------"
echo "  Hostname:    $TS_HOSTNAME"
echo "  Auth-Key:    ${AUTH_KEY:0:12}... (gekürzt)"
echo "  Tags:        ${TAGS:-keine}"
echo "  Exit-Node:   $EXIT_NODE"
echo "  SSH:         $ENABLE_SSH"
echo "  Shields Up:  $SHIELDS_UP"
echo "--------------------------------------------"
prompt "Fortfahren? [j/N]:"
read -rp "  > " CONFIRM
if [[ ! "$CONFIRM" =~ ^[jJ]$ ]]; then
  echo "Abgebrochen."
  exit 0
fi
echo ""

# ── Bereits installiert? ─────────────────────────────────────
if command -v tailscale &>/dev/null; then
  warning "Tailscale ist bereits installiert: $(tailscale version | head -1)"
  prompt "Neuinstallation / Aktualisierung fortsetzen? [j/N]:"
  read -rp "  > " REINSTALL
  if [[ ! "$REINSTALL" =~ ^[jJ]$ ]]; then
    info "Überspringe Installation — fahre mit tailscale up fort..."
    SKIP_INSTALL=true
  fi
fi

# ── Installation ─────────────────────────────────────────────
if [ "${SKIP_INSTALL:-false}" = false ]; then
  info "Füge Tailscale Repository hinzu..."

  # Offizielles Install-Script (pinned auf stable)
  curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.gpg \
    | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg

  curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.list \
    | tee /etc/apt/sources.list.d/tailscale.list > /dev/null

  apt-get update -qq
  apt-get install -y tailscale 2>/dev/null \
    || error "Installation fehlgeschlagen. Prüfe die Paketquellen."

  info "Tailscale installiert: $(tailscale version | head -1)"
fi

# ── IP-Forwarding für Exit-Node ──────────────────────────────
if [ "$EXIT_NODE" = true ]; then
  info "Aktiviere IP-Forwarding (erforderlich für Exit-Node)..."

  # IPv4
  if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  fi

  # IPv6
  if ! grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
  fi

  sysctl -p /etc/sysctl.conf > /dev/null
  info "IP-Forwarding aktiviert"
fi

# ── tailscale up Befehl zusammenbauen ───────────────────────
info "Verbinde mit Tailnet..."

UP_CMD="tailscale up"
UP_CMD+=" --authkey=${AUTH_KEY}"
UP_CMD+=" --hostname=${TS_HOSTNAME}"

[ -n "$TAGS" ]           && UP_CMD+=" --advertise-tags=${TAGS}"
[ "$EXIT_NODE" = true ]  && UP_CMD+=" --advertise-exit-node"
[ "$ENABLE_SSH" = true ] && UP_CMD+=" --ssh"
[ "$SHIELDS_UP" = true ] && UP_CMD+=" --shields-up"

# Ausführen (Auth-Key wird nicht geloggt)
eval "$UP_CMD" || error "tailscale up fehlgeschlagen. Prüfe den Auth-Key und die Netzwerkverbindung."

# ── Service sicherstellen ────────────────────────────────────
systemctl enable --now tailscaled > /dev/null 2>&1 || true

# ── Verifikation ─────────────────────────────────────────────
sleep 2

STATUS=$(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[^"]*"' | cut -d'"' -f4)
TS_IP=$(tailscale ip -4 2>/dev/null || echo "unbekannt")

if [ "$STATUS" = "Running" ]; then
  echo ""
  echo -e "${GREEN}[FERTIG]${NC} Tailscale verbunden"
  echo ""
  echo "  Tailscale IPv4:   $TS_IP"
  echo "  Hostname:         $TS_HOSTNAME"
  echo ""
  echo "  Status prüfen:    tailscale status"
  echo "  IP anzeigen:      tailscale ip"
  echo "  Verbindung prüfen: tailscale ping <anderer-host>"
  echo ""
  if [ "$EXIT_NODE" = true ]; then
    warning "Exit-Node: Muss im Tailscale Admin-Panel noch genehmigt werden."
    warning "  https://login.tailscale.com/admin/machines"
  fi
else
  error "Tailscale Status: '$STATUS' — Prüfe: tailscale status && journalctl -u tailscaled -n 30"
fi
