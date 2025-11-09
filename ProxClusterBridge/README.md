# ProxClusterBridge

> 🔗 Sicheres Multi-Site Proxmox Cluster Setup mit WireGuard VPN

ProxClusterBridge verbindet Proxmox-Server über verschiedene Standorte (z.B. Rechenzentrum + Home) sicher in einem Cluster. Mit automatischen Backups, Rollback-Funktionen und interaktivem Setup-Assistenten.

---

## 🎯 Features

- ✅ **Safe Mode** - Automatische Backups vor jeder Änderung
- ✅ **Rollback-Funktion** - Stelle alles mit einem Befehl wieder her
- ✅ **WireGuard VPN** - Sichere verschlüsselte Verbindung zwischen Standorten
- ✅ **Interaktiver Assistent** - Führt dich Schritt-für-Schritt durch das Setup
- ✅ **Pre-Flight Checks** - Prüft System vor Änderungen
- ✅ **Intelligente Erkennung** - Erkennt bestehende Konfigurationen
- ✅ **Keine Netzwerk-Änderungen** - Deine Bridge-Konfiguration bleibt unberührt

---

## 📋 Voraussetzungen

- 2x Proxmox VE Server (7.x oder 8.x)
- Root-Zugriff auf beiden Servern
- Öffentliche IP auf mindestens einem Server (Master)
- Offener UDP Port für WireGuard (Standard: 51820)

---

## 🚀 Quick Start

### 1. Script herunterladen

```bash
# Auf beiden Servern ausführen
cd /root
wget https://raw.githubusercontent.com/Stumpf-works/proxmox-toolkit/main/ProxClusterBridge/proxclusterbridge.sh
chmod +x proxclusterbridge.sh
```

### 2. Master-Server Setup (z.B. Hetzner)

```bash
sudo ./proxclusterbridge.sh
# Wähle Option 1 (Vollständiges Setup)
# Wähle "j" für Master-Node
```

**Notiere dir diese Informationen:**
- Master Public Key
- Master WireGuard IP
- Master Public IP

### 3. Worker-Server Setup (z.B. Home)

```bash
sudo ./proxclusterbridge.sh
# Wähle Option 1 (Vollständiges Setup)
# Wähle "n" für Worker-Node
# Gib Master-Informationen ein
```

### 4. Master aktualisieren

Füge auf dem **Master** in `/etc/wireguard/wg0.conf` hinzu:

```ini
[Peer]
PublicKey = <WORKER_PUBLIC_KEY>
AllowedIPs = <WORKER_WG_IP>/32
```

Dann WireGuard neu starten:

```bash
systemctl restart wg-quick@wg0
```

### 5. Worker dem Cluster hinzufügen

Auf dem **Worker** fortsetzten und dem Cluster beitreten.

---

## 📖 Detaillierte Anleitung

### Netzwerk-Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                                                               │
│  Master (Hetzner)              Worker (Home)                 │
│  ┌─────────────────┐          ┌─────────────────┐           │
│  │ Public IP       │          │ Private IP      │           │
│  │ 46.4.25.44      │          │ 192.168.1.100   │           │
│  │                 │          │                 │           │
│  │ vmbr0 (Bridges) │          │ vmbr0 (Bridges) │           │
│  │ vmbr1, vmbr2... │          │ vmbr1, vmbr2... │           │
│  │                 │          │                 │           │
│  │ wg0: 10.99.0.1  │◄────────►│ wg0: 10.99.0.2  │           │
│  └─────────────────┘ WireGuard └─────────────────┘           │
│         │                              │                     │
│         │                              │                     │
│         └──────────────────────────────┘                     │
│              Proxmox Cluster                                 │
│         (Corosync über WireGuard)                            │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Was wird geändert?

#### ✅ Wird hinzugefügt:
- Neues Interface: `wg0` (WireGuard VPN)
- WireGuard-Konfiguration: `/etc/wireguard/wg0.conf`
- iptables-Regeln für NAT (temporär, nur während WireGuard läuft)
- IP Forwarding in `/etc/sysctl.conf` (falls nicht schon aktiv)

#### ❌ Wird NICHT geändert:
- `/etc/network/interfaces` - Deine Bridge-Konfiguration bleibt unberührt
- Bestehende VMs und Container
- Firewall-Regeln (außer WireGuard-Port)
- Storage-Konfiguration
- Proxmox-Einstellungen

### Menü-Optionen

```
1) Vollständiges Setup (Empfohlen)
   → Installation + Konfiguration + Cluster-Setup
   
2) Nur WireGuard installieren
   → apt install wireguard
   
3) Nur WireGuard Keys generieren
   → Erstellt Public/Private Keys
   
4) Verbindung testen
   → Ping-Test zum anderen Node
   
5) System-Status anzeigen
   → Zeigt WireGuard + Cluster Status
   
6) WireGuard neu starten
   → systemctl restart wg-quick@wg0
   
7) Backup erstellen (manuell)
   → Erstellt Sicherheitskopie ohne Änderungen
   
8) Rollback durchführen
   → Stellt vorheriges Backup wieder her
```

---

## 🔧 Manuelle Konfiguration

### WireGuard manuell testen

```bash
# Status prüfen
wg show

# Logs anschauen
journalctl -u wg-quick@wg0 -f

# Verbindung testen
ping 10.99.0.1  # Master
ping 10.99.0.2  # Worker
```

### Cluster-Status prüfen

```bash
# Cluster-Status
pvecm status

# Alle Nodes anzeigen
pvecm nodes

# Quorum-Status
pvecm expected 2
```

---

## 🛠️ Troubleshooting

### Problem: Keine Verbindung zwischen Nodes

**Lösung:**

```bash
# 1. WireGuard Status prüfen
systemctl status wg-quick@wg0
wg show

# 2. Firewall prüfen
iptables -L -n -v | grep 51820

# 3. Routing prüfen
ip route

# 4. Logs checken
journalctl -u wg-quick@wg0 --no-pager -n 50
```

### Problem: Cluster-Join schlägt fehl

**Mögliche Ursachen:**

1. **WireGuard-Verbindung nicht aktiv**
   ```bash
   ping 10.99.0.1  # Von Worker zum Master
   ```

2. **SSH funktioniert nicht**
   ```bash
   ssh root@10.99.0.1  # Teste SSH-Verbindung
   ```

3. **Falsches Passwort**
   - `pvecm add` benötigt Root-Passwort des Masters

4. **Ports nicht offen**
   - TCP 22 (SSH)
   - TCP 8006 (Proxmox Web)
   - UDP 5404-5405 (Corosync)

### Problem: WireGuard startet nicht

```bash
# Konfiguration testen
wg-quick up wg0

# Fehler in Config?
cat /etc/wireguard/wg0.conf

# Interface-Konflikt?
ip link show wg0
```

---

## 🔙 Rollback

Falls etwas schiefgeht:

```bash
# Option 8 im Menü wählen
sudo ./proxclusterbridge.sh
# → 8) Rollback durchführen

# Oder manuell:
# 1. WireGuard stoppen
systemctl stop wg-quick@wg0
systemctl disable wg-quick@wg0

# 2. Backup wiederherstellen
BACKUP_DIR="/root/proxclusterbridge-backup-YYYYMMDD-HHMMSS"
cp $BACKUP_DIR/interfaces.backup /etc/network/interfaces
cp $BACKUP_DIR/hostname.backup /etc/hostname
hostnamectl set-hostname $(cat $BACKUP_DIR/hostname.backup)

# 3. System neu starten
reboot
```

---

## 📊 Backup-Struktur

Das Script erstellt automatisch Backups in:

```
/root/proxclusterbridge-backup-20250109-143022/
├── hostname.backup           # Alter Hostname
├── interfaces.backup         # /etc/network/interfaces
├── hosts.backup             # /etc/hosts
├── sysctl.backup            # Sysctl-Einstellungen
├── services.backup          # Aktive Services
├── pve.tar.gz              # /etc/pve Konfiguration
├── wireguard.tar.gz        # /etc/wireguard (falls vorhanden)
└── rollback.log            # Rollback-Informationen
```

---

## ⚙️ Konfigurationsdateien

### Master: `/etc/wireguard/wg0.conf`

```ini
[Interface]
PrivateKey = <MASTER_PRIVATE_KEY>
Address = 10.99.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o vmbr0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o vmbr0 -j MASQUERADE

[Peer]
PublicKey = <WORKER_PUBLIC_KEY>
AllowedIPs = 10.99.0.2/32
```

### Worker: `/etc/wireguard/wg0.conf`

```ini
[Interface]
PrivateKey = <WORKER_PRIVATE_KEY>
Address = 10.99.0.2/24
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o vmbr0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o vmbr0 -j MASQUERADE

[Peer]
PublicKey = <MASTER_PUBLIC_KEY>
Endpoint = <MASTER_PUBLIC_IP>:51820
AllowedIPs = 10.99.0.1/32, 10.99.0.0/24
PersistentKeepalive = 25
```

---

## 🔒 Sicherheit

### Best Practices

1. **Firewall-Regeln**
   ```bash
   # Nur WireGuard-Port von außen erreichbar
   ufw allow 51820/udp
   
   # Proxmox nur über WireGuard
   ufw allow from 10.99.0.0/24 to any port 8006
   ```

2. **SSH-Zugriff absichern**
   ```bash
   # Nur Key-basierte Auth
   # In /etc/ssh/sshd_config:
   PasswordAuthentication no
   ```

3. **Regelmäßige Updates**
   ```bash
   apt update && apt upgrade -y
   ```

4. **Monitoring**
   ```bash
   # WireGuard-Traffic überwachen
   watch -n 1 wg show
   ```

---

## 📝 FAQ

**Q: Kann ich mehr als 2 Server verbinden?**
A: Ja! Füge einfach weitere Peer-Sections in der WireGuard-Config hinzu.

**Q: Funktioniert das auch mit Proxmox 7.x?**
A: Ja, getestet mit Proxmox 7.4 und 8.x.

**Q: Was passiert wenn die WireGuard-Verbindung abbricht?**
A: Der Cluster wird als "quorum lost" markiert. VMs laufen weiter, aber keine Cluster-Operationen möglich.

**Q: Kann ich bestehende Cluster erweitern?**
A: Vorsicht! Backup erstellen und testen. Besser: Neues Cluster mit Migration.

**Q: Werden meine VMs unterbrochen?**
A: Nein, VMs laufen während des gesamten Setups weiter.

**Q: Kann ich IPv6 nutzen?**
A: Ja, WireGuard unterstützt IPv6. Passe die Config entsprechend an.

---

## 🤝 Contributing

Dieses Tool ist Teil des [Proxmox Toolkit](https://github.com/Stumpf-works/proxmox-toolkit) Repository.

Bugs oder Feature-Requests? → [Issue erstellen](https://github.com/Stumpf-works/proxmox-toolkit/issues)

---

## 📜 Lizenz

MIT License - siehe [LICENSE](../LICENSE) Datei im Hauptverzeichnis.

---

## 👨‍💻 Autor

**Sebastian Stumpf**
- GitHub: [@Stumpf-works](https://github.com/Stumpf-works)
- Website: [Stumpf.works](https://stumpf.works)

---

## ⚠️ Haftungsausschluss

Dieses Tool wird "as is" bereitgestellt. Teste es immer erst in einer Test-Umgebung!
Erstelle IMMER Backups vor produktiven Änderungen.

---

## 🙏 Credits

- [WireGuard](https://www.wireguard.com/) - Moderne VPN-Technologie
- [Proxmox VE](https://www.proxmox.com/) - Virtualisierungsplattform
- Community-Feedback und Testing

---

**⭐ Wenn dir dieses Tool hilft, lass einen Star im [Proxmox Toolkit](https://github.com/Stumpf-works/proxmox-toolkit) da!**