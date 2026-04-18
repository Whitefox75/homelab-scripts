# homelab-scripts

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012-orange.svg)

Automatisierungsskripte für den Aufbau und Betrieb einer Linux-basierten Homelab-Infrastruktur auf Basis von Proxmox. Alle Skripte sind interaktiv, enthalten keine hardcoded Credentials und unterstützen alternativ die Übergabe von Parametern via Flags oder Umgebungsvariablen.

---

## Infrastruktur-Übersicht

```
Proxmox Host
├── LXC: Monitoring (Debian 12)
│   ├── Prometheus        :9090
│   ├── Grafana           :3000
│   └── pve_exporter      :9221
├── VM: Wazuh SIEM (Debian 12)
│   └── node_exporter     :9100
└── VM: Weitere Hosts
    ├── Tailscale
    └── node_exporter     :9100
```

---

## Dateistruktur

```
homelab-scripts/
├── setup.sh                   # Zentrales Setup-Script (Empfehlung)
├── tailscale_install.sh       # Tailscale Installation & Verbindung
├── node_exporter_install.sh   # Prometheus node_exporter Installation
├── wazuh_agent_deploy.sh      # Wazuh SIEM Agent Installation
└── prometheus.yml             # Prometheus Konfigurationsvorlage
```

---

## Schnellstart

Für neue VMs ist `setup.sh` der empfohlene Einstiegspunkt. Es führt durch alle verfügbaren Schritte in einem interaktiven Menü — von der Grundkonfiguration bis zur Dienst-Installation.

**Voraussetzungen:**
- Debian 12 (Bookworm)
- Root-Rechte
- Internetzugang
- Alle Skripte im selben Verzeichnis

```bash
git clone https://github.com/Whitefox75/homelab-scripts.git
cd homelab-scripts
sudo bash setup.sh
```

Das Hauptmenü bietet folgende Optionen:

```
[1]  System einrichten (Updates, UFW, fail2ban, ...)
[2]  Tailscale installieren
[3]  node_exporter installieren
[4]  Wazuh Agent installieren
[5]  Alles installieren (empfohlen für neue VM)
[6]  Zusammenfassung anzeigen
[0]  Beenden
```

Option `[5]` führt alle Schritte in der empfohlenen Reihenfolge aus: Grundkonfiguration → Tailscale → node_exporter → Wazuh Agent.

---

## Einzelne Skripte

Alle Skripte können unabhängig von `setup.sh` ausgeführt werden. Parameter können als Flags übergeben, als Umgebungsvariablen gesetzt oder interaktiv eingegeben werden.

---

### setup.sh — Grundkonfiguration

Der Abschnitt `[1] System einrichten` deckt folgende Punkte ab, die einzeln aktiviert werden können:

| Punkt | Beschreibung |
|---|---|
| Unattended-Upgrades | Automatische Security-Updates via `apt` |
| UFW Firewall | Basisregeln inkl. vorkonfigurierter Ports für alle Dienste |
| fail2ban | Automatisches Sperren bei fehlgeschlagenen SSH-Logins |
| Zeitzone | Systemzeitzone setzen |
| Hostname | Hostname und `/etc/hosts` aktualisieren |
| Sudo-User | Neuen Benutzer mit sudo-Rechten anlegen |
| qemu-guest-agent | Proxmox-Integration für QEMU-VMs |

Die UFW-Regeln sind so vorkonfiguriert, dass alle in diesem Repository enthaltenen Dienste ohne manuelle Nacharbeit kommunizieren können (SSH, node_exporter Port 9100, Wazuh Ports 1514/1515, Tailscale UDP 41641).

---

### tailscale_install.sh

Installiert Tailscale aus dem offiziellen Debian-Repository und verbindet die VM mit dem Tailnet.

```bash
# Interaktiv
sudo bash tailscale_install.sh

# Mit Flags
sudo bash tailscale_install.sh \
  --auth-key tskey-auth-xxxx \
  --hostname meine-vm \
  --tags tag:server,tag:homelab \
  --ssh

# Mit Umgebungsvariablen
TS_AUTH_KEY=tskey-auth-xxxx TS_HOSTNAME=meine-vm sudo bash tailscale_install.sh
```

**Verfügbare Flags:**

| Flag | Env-Variable | Beschreibung |
|---|---|---|
| `-k`, `--auth-key` | `TS_AUTH_KEY` | Tailscale Auth-Key |
| `-h`, `--hostname` | `TS_HOSTNAME` | Hostname im Tailnet |
| `-t`, `--tags` | `TS_TAGS` | ACL-Tags (kommagetrennt) |
| `-e`, `--exit-node` | — | VM als Exit-Node registrieren |
| `-s`, `--ssh` | — | Tailscale SSH aktivieren |
| `--shields-up` | — | Nur ausgehende Verbindungen erlauben |

Auth-Keys werden unter [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) erstellt. Bei Verwendung von `--exit-node` muss die VM zusätzlich im [Tailscale Admin-Panel](https://login.tailscale.com/admin/machines) genehmigt werden.

---

### node_exporter_install.sh

Installiert den [Prometheus node_exporter](https://github.com/prometheus/node_exporter). Die aktuelle Version wird automatisch von der GitHub API ermittelt und kann interaktiv überschrieben werden.

```bash
# Interaktiv (empfohlene Methode)
sudo bash node_exporter_install.sh

# Mit spezifischer Version via Flag
sudo bash node_exporter_install.sh --version 1.11.1

# Mit Umgebungsvariable
NODE_EXPORTER_VERSION=1.11.1 sudo bash node_exporter_install.sh
```

Das Skript legt einen dedizierten System-User `node_exporter` ohne Login-Shell an, installiert die Binary nach `/usr/local/bin/` und richtet einen systemd-Service ein. Nach der Installation sind die Metriken unter `http://<ip>:9100/metrics` erreichbar.

---

### wazuh_agent_deploy.sh

Installiert und registriert einen [Wazuh](https://wazuh.com) SIEM-Agent. Richtet das offizielle Wazuh APT-Repository ein und trägt die Manager-IP automatisch in `ossec.conf` ein.

**Voraussetzung:** Ein laufender Wazuh Manager ist erforderlich.

```bash
# Interaktiv
sudo bash wazuh_agent_deploy.sh

# Mit Flags
sudo bash wazuh_agent_deploy.sh \
  --manager-ip 192.168.1.100 \
  --name meine-vm \
  --version 4.14.3

# Mit Umgebungsvariablen (für automatisiertes Deployment)
WAZUH_MANAGER_IP=192.168.1.100 \
WAZUH_AGENT_NAME=meine-vm \
WAZUH_VERSION=4.14.3 \
sudo bash wazuh_agent_deploy.sh
```

**Verfügbare Flags:**

| Flag | Env-Variable | Beschreibung |
|---|---|---|
| `-m`, `--manager-ip` | `WAZUH_MANAGER_IP` | IP-Adresse des Wazuh Managers |
| `-n`, `--name` | `WAZUH_AGENT_NAME` | Name des Agents im Manager |
| `-v`, `--version` | `WAZUH_VERSION` | Wazuh Agent Version |

> Nach der Installation muss der Agent im Wazuh Manager unter **Agents → Pending** manuell genehmigt werden.

---

### prometheus.yml

Konfigurationsvorlage für Prometheus mit vorkonfigurierten Scrape-Jobs. Vor der Verwendung müssen drei Platzhalter durch die tatsächlichen IP-Adressen ersetzt werden.

| Platzhalter | Beschreibung |
|---|---|
| `<wazuh-vm-ip>` | IP-Adresse der Wazuh VM |
| `<tailscale-vm-ip>` | IP-Adresse der Tailscale VM |
| `<proxmox-host-ip>` | IP-Adresse des Proxmox Hosts |

```bash
# Vorlage nach /etc/prometheus/ kopieren und anpassen
cp prometheus.yml /etc/prometheus/prometheus.yml
nano /etc/prometheus/prometheus.yml

# Konfiguration validieren
promtool check config /etc/prometheus/prometheus.yml

# Prometheus neu laden
systemctl reload prometheus
```

**Enthaltene Scrape-Jobs:**

| Job | Target | Port |
|---|---|---|
| `prometheus` | Self-Monitoring | 9090 |
| `node_wazuh` | Wazuh VM | 9100 |
| `node_tailscale` | Tailscale VM | 9100 |
| `pve` | Proxmox Host via pve_exporter | 9221 |

---

## Sicherheitshinweise

- Keine hardcoded IP-Adressen, Passwörter oder API-Keys in den Skripten
- Sensible Parameter (Auth-Keys, Passwörter) werden verdeckt eingegeben und nicht geloggt
- Konfigurationsvorlagen verwenden ausschließlich Platzhalter
- Skripte sind ausschließlich für autorisierte Systeme bestimmt

---

## Getestete Umgebungen

| OS | Architektur | Status |
|---|---|---|
| Debian 12 (Bookworm) | amd64 | Getestet |

---

## Lizenz

MIT License — freie Verwendung, Veränderung und Weitergabe.
