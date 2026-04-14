# homelab-scripts

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-orange.svg)

Automatisierungsskripte für den Aufbau und Betrieb einer Linux-basierten Homelab-Infrastruktur.  
Alle Skripte sind auf Debian/Ubuntu ausgelegt, enthalten keine hardcoded Credentials und fragen sensible Parameter interaktiv ab.

---

## Inhalt

```
homelab-scripts/
├── monitoring/
│   └── node_exporter_install.sh   # Prometheus node_exporter Installation
├── security/
│   └── wazuh_agent_deploy.sh      # Wazuh SIEM Agent Installation & Registrierung
└── README.md
```

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
    └── node_exporter     :9100
```

---

## Skripte

### monitoring/node_exporter_install.sh

Installiert [Prometheus node_exporter](https://github.com/prometheus/node_exporter) auf einem Debian/Ubuntu System.  
Ermittelt automatisch die aktuellste Version von GitHub.

**Voraussetzungen:**
- Debian 12 / Ubuntu 22.04+
- Root-Rechte
- Internetzugang

**Verwendung:**

```bash
# Interaktiv (Version wird automatisch ermittelt)
sudo bash node_exporter_install.sh

# Mit spezifischer Version
NODE_EXPORTER_VERSION=1.11.1 sudo bash node_exporter_install.sh
```

**Direkt von GitHub ausführen:**

```bash
curl -sO https://raw.githubusercontent.com/Whitefox75/homelab-scripts/main/monitoring/node_exporter_install.sh
sudo bash node_exporter_install.sh
```

**Was das Skript macht:**
1. Aktuelle Version von GitHub API ermitteln
2. Dedizierten System-User `node_exporter` anlegen (kein Login, keine Shell)
3. Binary herunterladen und nach `/usr/local/bin/` installieren
4. systemd Unit-File erstellen und Service aktivieren
5. Erreichbarkeit auf Port `9100` verifizieren

---

### security/wazuh_agent_deploy.sh

Installiert und registriert einen [Wazuh](https://wazuh.com) SIEM Agent auf einem Debian/Ubuntu System.

**Voraussetzungen:**
- Debian 12 / Ubuntu 22.04+
- Root-Rechte
- Internetzugang
- Laufender Wazuh Manager

**Verwendung:**

```bash
# Interaktiv — Skript fragt Manager IP, Agent Name und Version ab
sudo bash wazuh_agent_deploy.sh

# Mit Umgebungsvariablen (für automatisiertes Deployment)
WAZUH_MANAGER_IP=<manager-ip> \
WAZUH_AGENT_NAME=<agent-name> \
WAZUH_VERSION=4.14.3 \
sudo bash wazuh_agent_deploy.sh
```

**Direkt von GitHub ausführen:**

```bash
curl -sO https://raw.githubusercontent.com/Whitefox75/homelab-scripts/main/security/wazuh_agent_deploy.sh
sudo bash wazuh_agent_deploy.sh
```

**Was das Skript macht:**
1. Manager IP, Agent Name und Version interaktiv abfragen
2. Wazuh APT Repository und GPG Key einrichten
3. Wazuh Agent installieren
4. Manager IP und Agent Name in `ossec.conf` eintragen
5. Service via systemd aktivieren
6. Hinweis ausgeben dass der Agent im Manager genehmigt werden muss

> **Hinweis:** Nach der Installation muss der Agent im Wazuh Manager unter  
> `Agents → Pending` manuell genehmigt werden.

---

## Sicherheitshinweise

- Alle Skripte enthalten **keine** hardcoded IP-Adressen, Passwörter oder API-Keys
- Sensible Parameter werden interaktiv abgefragt oder via Umgebungsvariablen übergeben
- Dienste laufen unter dedizierten unprivilegierten System-Usern (kein root)
- Skripte sind ausschließlich für **autorisierte Systeme** gedacht

---

## Getestete Umgebungen

| OS | Architektur | Status |
|---|---|---|
| Debian 12 (Bookworm) | amd64 | ✅ Getestet |

---

## Beitragen

Pull Requests und Issues sind willkommen.  
Bitte stelle sicher dass neue Skripte keine Credentials enthalten und auf Debian 12 getestet sind.

---

## Lizenz

MIT License — freie Verwendung, Veränderung und Weitergabe.
