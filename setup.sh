#!/bin/bash
# ============================================================
# setup.sh
# Zentrales Setup-Script für neue Debian 12 VMs
#
# Verwendung: sudo bash setup.sh
#
# Enthält:
#   A) Grundkonfiguration (Unattended-Upgrades, UFW, fail2ban,
#      Zeitzone, Hostname, Sudo-User, qemu-guest-agent)
#   B) Dienste (Tailscale, node_exporter, Wazuh Agent)
# ============================================================

set -e

# ── Farben ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}[*]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[FEHLER]${NC} $1"; exit 1; }
prompt()  { echo -e "${CYAN}[?]${NC} $1"; }
header()  { echo -e "\n${BLUE}${BOLD}══ $1 ══${NC}\n"; }
success() { echo -e "${GREEN}${BOLD}[✔]${NC} $1"; }

# ── Root-Prüfung ─────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  error "Dieses Skript muss als root ausgeführt werden (sudo bash $0)"
fi

# ── Skript-Verzeichnis ermitteln ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Hilfsfunktionen ──────────────────────────────────────────
press_enter() {
  echo ""
  read -rp "  Enter drücken um fortzufahren..."
}

confirm() {
  # $1 = Frage, gibt 0 (ja) oder 1 (nein) zurück
  prompt "$1 [j/N]:"
  read -rp "  > " _confirm
  [[ "$_confirm" =~ ^[jJ]$ ]]
}

# Status-Tracking
declare -A INSTALLED
INSTALLED=(
  [grundkonfig]=false
  [tailscale]=false
  [node_exporter]=false
  [wazuh]=false
)

# ── UFW Regeln für Dienste ───────────────────────────────────
configure_ufw_rules() {
  info "Konfiguriere UFW Basisregeln..."

  ufw --force reset > /dev/null

  # Standard-Policies
  ufw default deny incoming > /dev/null
  ufw default allow outgoing > /dev/null

  # SSH immer erlauben (vor enable!)
  ufw allow ssh > /dev/null
  info "Regel gesetzt: SSH (22/tcp)"

  # node_exporter (Prometheus scraping)
  ufw allow 9100/tcp comment 'node_exporter' > /dev/null
  info "Regel gesetzt: node_exporter (9100/tcp)"

  # Wazuh Agent → Manager Kommunikation
  ufw allow out 1514/tcp comment 'wazuh-agent' > /dev/null
  ufw allow out 1514/udp comment 'wazuh-agent' > /dev/null
  ufw allow out 1515/tcp comment 'wazuh-agent-enroll' > /dev/null
  info "Regel gesetzt: Wazuh Agent (1514, 1515 outbound)"

  # Tailscale (UDP)
  ufw allow 41641/udp comment 'tailscale' > /dev/null
  info "Regel gesetzt: Tailscale (41641/udp)"

  # UFW aktivieren
  ufw --force enable > /dev/null
  success "UFW aktiviert"
  echo ""
  ufw status numbered
}

# ════════════════════════════════════════════════════════════
# GRUNDKONFIGURATION
# ════════════════════════════════════════════════════════════

run_grundkonfig() {
  header "Grundkonfiguration"

  # ── Paketliste aktualisieren ─────────────────────────────
  info "Aktualisiere Paketliste..."
  apt-get update -qq

  # ── Menü Grundkonfiguration ──────────────────────────────
  local STEPS=()
  local DO_UPGRADES=false
  local DO_UFW=false
  local DO_FAIL2BAN=false
  local DO_TIMEZONE=false
  local DO_HOSTNAME=false
  local DO_USER=false
  local DO_QEMU=false

  echo "  Welche Grundkonfigurationen sollen durchgeführt werden?"
  echo ""

  confirm "  [1] Unattended-Upgrades (automatische Security-Updates)" && DO_UPGRADES=true
  confirm "  [2] UFW Firewall einrichten (Basisregeln)" && DO_UFW=true
  confirm "  [3] fail2ban installieren" && DO_FAIL2BAN=true
  confirm "  [4] Zeitzone setzen" && DO_TIMEZONE=true
  confirm "  [5] Hostname setzen" && DO_HOSTNAME=true
  confirm "  [6] Sudo-User anlegen" && DO_USER=true
  confirm "  [7] qemu-guest-agent installieren (Proxmox)" && DO_QEMU=true

  echo ""

  # ── Unattended-Upgrades ──────────────────────────────────
  if [ "$DO_UPGRADES" = true ]; then
    header "Unattended-Upgrades"
    apt-get install -y unattended-upgrades apt-listchanges > /dev/null
    dpkg-reconfigure -plow unattended-upgrades
    # Reboot-Verhalten konfigurieren
    UPGRADES_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
    if [ -f "$UPGRADES_CONF" ]; then
      # Automatischen Reboot deaktivieren (VM-Kontext)
      sed -i 's|//Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "false";|' "$UPGRADES_CONF" || true
    fi
    success "Unattended-Upgrades aktiviert (kein automatischer Reboot)"
  fi

  # ── UFW ──────────────────────────────────────────────────
  if [ "$DO_UFW" = true ]; then
    header "UFW Firewall"
    if ! command -v ufw &>/dev/null; then
      apt-get install -y ufw > /dev/null
    fi
    configure_ufw_rules
    success "UFW konfiguriert"
  fi

  # ── fail2ban ─────────────────────────────────────────────
  if [ "$DO_FAIL2BAN" = true ]; then
    header "fail2ban"
    apt-get install -y fail2ban > /dev/null

    # Lokale Konfiguration anlegen (überschreibt nicht fail2ban.conf bei Updates)
    cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
EOF

    systemctl enable --now fail2ban > /dev/null
    success "fail2ban installiert und aktiviert (SSH: 5 Versuche → 1h Ban)"
  fi

  # ── Zeitzone ─────────────────────────────────────────────
  if [ "$DO_TIMEZONE" = true ]; then
    header "Zeitzone"
    CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unbekannt")
    info "Aktuelle Zeitzone: $CURRENT_TZ"
    prompt "Zeitzone eingeben [Standard: Europe/Berlin]:"
    read -rp "  > " NEW_TZ
    NEW_TZ="${NEW_TZ:-Europe/Berlin}"
    if timedatectl set-timezone "$NEW_TZ" 2>/dev/null; then
      success "Zeitzone gesetzt: $NEW_TZ"
    else
      warning "Ungültige Zeitzone: $NEW_TZ — übersprungen"
    fi
  fi

  # ── Hostname ─────────────────────────────────────────────
  if [ "$DO_HOSTNAME" = true ]; then
    header "Hostname"
    CURRENT_HOST=$(hostname)
    info "Aktueller Hostname: $CURRENT_HOST"
    prompt "Neuen Hostname eingeben:"
    read -rp "  > " NEW_HOST
    if [ -n "$NEW_HOST" ]; then
      hostnamectl set-hostname "$NEW_HOST"
      # /etc/hosts aktualisieren
      if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOST/" /etc/hosts
      else
        echo -e "127.0.1.1\t$NEW_HOST" >> /etc/hosts
      fi
      success "Hostname gesetzt: $NEW_HOST"
    else
      warning "Kein Hostname eingegeben — übersprungen"
    fi
  fi

  # ── Sudo-User ────────────────────────────────────────────
  if [ "$DO_USER" = true ]; then
    header "Sudo-User anlegen"
    prompt "Benutzername eingeben:"
    read -rp "  > " NEW_USER
    if [ -z "$NEW_USER" ]; then
      warning "Kein Benutzername eingegeben — übersprungen"
    elif id "$NEW_USER" &>/dev/null; then
      warning "User '$NEW_USER' existiert bereits"
      confirm "  sudo-Gruppe hinzufügen?" && usermod -aG sudo "$NEW_USER" && success "User '$NEW_USER' zur sudo-Gruppe hinzugefügt"
    else
      adduser --gecos "" "$NEW_USER"
      usermod -aG sudo "$NEW_USER"
      success "User '$NEW_USER' angelegt und sudo-Gruppe hinzugefügt"
    fi
  fi

  # ── qemu-guest-agent ─────────────────────────────────────
  if [ "$DO_QEMU" = true ]; then
    header "qemu-guest-agent"
    apt-get install -y qemu-guest-agent > /dev/null
    systemctl enable --now qemu-guest-agent > /dev/null
    success "qemu-guest-agent installiert und aktiviert"
  fi

  INSTALLED[grundkonfig]=true
  success "Grundkonfiguration abgeschlossen"
  press_enter
}

# ════════════════════════════════════════════════════════════
# TAILSCALE
# ════════════════════════════════════════════════════════════

run_tailscale() {
  header "Tailscale Installation"

  local SCRIPT="$SCRIPT_DIR/tailscale_install.sh"
  if [ ! -f "$SCRIPT" ]; then
    error "tailscale_install.sh nicht gefunden unter: $SCRIPT"
  fi

  bash "$SCRIPT"
  INSTALLED[tailscale]=true
  press_enter
}

# ════════════════════════════════════════════════════════════
# NODE_EXPORTER
# ════════════════════════════════════════════════════════════

run_node_exporter() {
  header "node_exporter Installation"

  local SCRIPT="$SCRIPT_DIR/node_exporter_install.sh"
  if [ ! -f "$SCRIPT" ]; then
    error "node_exporter_install.sh nicht gefunden unter: $SCRIPT"
  fi

  bash "$SCRIPT"
  INSTALLED[node_exporter]=true
  press_enter
}

# ════════════════════════════════════════════════════════════
# WAZUH AGENT
# ════════════════════════════════════════════════════════════

run_wazuh() {
  header "Wazuh Agent Installation"

  local SCRIPT="$SCRIPT_DIR/wazuh_agent_deploy.sh"
  if [ ! -f "$SCRIPT" ]; then
    error "wazuh_agent_deploy.sh nicht gefunden unter: $SCRIPT"
  fi

  bash "$SCRIPT"
  INSTALLED[wazuh]=true
  press_enter
}

# ════════════════════════════════════════════════════════════
# ALLES INSTALLIEREN
# ════════════════════════════════════════════════════════════

run_all() {
  header "Vollständiges Setup"
  warning "Führt alle Schritte nacheinander aus:"
  echo "    1. Grundkonfiguration"
  echo "    2. Tailscale"
  echo "    3. node_exporter"
  echo "    4. Wazuh Agent"
  echo ""

  if ! confirm "Alle Schritte jetzt ausführen?"; then
    return
  fi

  run_grundkonfig
  run_tailscale
  run_node_exporter
  run_wazuh
}

# ════════════════════════════════════════════════════════════
# ZUSAMMENFASSUNG
# ════════════════════════════════════════════════════════════

show_summary() {
  header "Installations-Zusammenfassung"

  local STATUS_GRUNDKONFIG="${INSTALLED[grundkonfig]}"
  local STATUS_TAILSCALE="${INSTALLED[tailscale]}"
  local STATUS_NODE="${INSTALLED[node_exporter]}"
  local STATUS_WAZUH="${INSTALLED[wazuh]}"

  _status() {
    [ "$1" = true ] && echo -e "${GREEN}✔ Abgeschlossen${NC}" || echo -e "${YELLOW}– Übersprungen${NC}"
  }

  echo -e "  Grundkonfiguration:  $(_status $STATUS_GRUNDKONFIG)"
  echo -e "  Tailscale:           $(_status $STATUS_TAILSCALE)"
  echo -e "  node_exporter:       $(_status $STATUS_NODE)"
  echo -e "  Wazuh Agent:         $(_status $STATUS_WAZUH)"
  echo ""

  if [ "$STATUS_TAILSCALE" = true ]; then
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "nicht verfügbar")
    info "Tailscale IP: $TS_IP"
  fi

  if [ "$STATUS_NODE" = true ]; then
    info "node_exporter Metriken: curl http://localhost:9100/metrics | head -5"
  fi

  if [ "$STATUS_WAZUH" = true ]; then
    warning "Wazuh Agent muss im Manager unter 'Agents → Pending' genehmigt werden"
  fi
}

# ════════════════════════════════════════════════════════════
# HAUPTMENÜ
# ════════════════════════════════════════════════════════════

main_menu() {
  while true; do
    clear
    echo ""
    echo -e "${BLUE}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║         Homelab VM Setup Script          ║"
    echo "  ║              Debian 12                   ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}Grundkonfiguration${NC}"
    echo "  [1]  System einrichten (Updates, UFW, fail2ban, ...)"
    echo ""
    echo -e "  ${BOLD}Dienste${NC}"
    echo "  [2]  Tailscale installieren"
    echo "  [3]  node_exporter installieren"
    echo "  [4]  Wazuh Agent installieren"
    echo ""
    echo -e "  ${BOLD}Komplett${NC}"
    echo "  [5]  Alles installieren (Empfohlen für neue VM)"
    echo ""
    echo -e "  ${BOLD}Sonstiges${NC}"
    echo "  [6]  Zusammenfassung anzeigen"
    echo "  [0]  Beenden"
    echo ""

    # Aktuelle Status-Anzeige
    echo -e "  ${BOLD}Status:${NC}"
    for key in grundkonfig tailscale node_exporter wazuh; do
      label="$key"
      [ "$key" = "grundkonfig" ] && label="Grundkonfig  "
      [ "$key" = "tailscale" ]   && label="Tailscale    "
      [ "$key" = "node_exporter" ] && label="node_exporter"
      [ "$key" = "wazuh" ]       && label="Wazuh Agent  "
      if [ "${INSTALLED[$key]}" = true ]; then
        echo -e "    $label  ${GREEN}✔${NC}"
      else
        echo -e "    $label  ${YELLOW}–${NC}"
      fi
    done
    echo ""

    prompt "Auswahl:"
    read -rp "  > " CHOICE

    case "$CHOICE" in
      1) run_grundkonfig ;;
      2) run_tailscale ;;
      3) run_node_exporter ;;
      4) run_wazuh ;;
      5) run_all ;;
      6) show_summary; press_enter ;;
      0)
        echo ""
        show_summary
        echo ""
        info "Setup beendet."
        echo ""
        exit 0
        ;;
      *)
        warning "Ungültige Eingabe: '$CHOICE'"
        sleep 1
        ;;
    esac
  done
}

# ── Start ────────────────────────────────────────────────────
main_menu
