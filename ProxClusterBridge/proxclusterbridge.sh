#!/bin/bash

################################################################################
# ProxClusterBridge v1.0 - Safe Multi-Site Proxmox Cluster Setup
# 
# Verbindet Proxmox-Server über verschiedene Standorte sicher via WireGuard VPN
# Mit automatischen Backups und Rollback-Funktionen
#
# Repository: https://github.com/YourUsername/ProxClusterBridge
# Author: Sebastian Stumpf
# License: MIT
################################################################################

set -e

# Farben für Output
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

# Backup-Verzeichnis
BACKUP_DIR="/root/proxclusterbridge-backup-$(date +%Y%m%d-%H%M%S)"
ROLLBACK_LOG="$BACKUP_DIR/rollback.log"

# Log-Funktionen
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[✓ SUCCESS]${COLOR_RESET} $1"
}

log_warning() {
    echo -e "${COLOR_YELLOW}[⚠ WARNING]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[✗ ERROR]${COLOR_RESET} $1"
}

log_step() {
    echo -e "${COLOR_CYAN}[STEP]${COLOR_RESET} $1"
}

# Backup-Funktionen
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_success "Backup-Verzeichnis erstellt: $BACKUP_DIR"
    fi
}

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/$(basename $file).backup"
        log_info "Gesichert: $file"
        echo "FILE:$file" >> "$ROLLBACK_LOG"
    fi
}

backup_directory() {
    local dir="$1"
    if [ -d "$dir" ]; then
        tar -czf "$BACKUP_DIR/$(basename $dir).tar.gz" "$dir" 2>/dev/null || true
        log_info "Gesichert: $dir"
        echo "DIR:$dir" >> "$ROLLBACK_LOG"
    fi
}

create_full_backup() {
    log_step "Erstelle Sicherheitskopie..."
    create_backup_dir
    
    # Hostname sichern
    hostname > "$BACKUP_DIR/hostname.backup"
    
    # Netzwerk-Konfiguration
    backup_file "/etc/network/interfaces"
    backup_file "/etc/hosts"
    backup_file "/etc/hostname"
    
    # Proxmox-Konfiguration
    if [ -d "/etc/pve" ]; then
        backup_directory "/etc/pve"
    fi
    
    # WireGuard (falls vorhanden)
    if [ -d "/etc/wireguard" ]; then
        backup_directory "/etc/wireguard"
    fi
    
    # Systemctl Status
    systemctl list-units --type=service --state=running > "$BACKUP_DIR/services.backup"
    
    # Sysctl Settings
    sysctl -a > "$BACKUP_DIR/sysctl.backup" 2>/dev/null || true
    
    log_success "Backup erstellt in: $BACKUP_DIR"
    echo ""
    log_warning "Speichere diesen Pfad für einen eventuellen Rollback!"
    echo ""
}

perform_rollback() {
    log_warning "Starte Rollback-Prozess..."
    
    read -p "Backup-Verzeichnis Pfad: " RESTORE_DIR
    
    if [ ! -d "$RESTORE_DIR" ]; then
        log_error "Backup-Verzeichnis nicht gefunden!"
        return 1
    fi
    
    # Hostname wiederherstellen
    if [ -f "$RESTORE_DIR/hostname.backup" ]; then
        hostnamectl set-hostname "$(cat $RESTORE_DIR/hostname.backup)"
        log_info "Hostname wiederhergestellt"
    fi
    
    # Network interfaces wiederherstellen
    if [ -f "$RESTORE_DIR/interfaces.backup" ]; then
        cp "$RESTORE_DIR/interfaces.backup" /etc/network/interfaces
        log_info "Network interfaces wiederhergestellt"
    fi
    
    # Hosts wiederherstellen
    if [ -f "$RESTORE_DIR/hosts.backup" ]; then
        cp "$RESTORE_DIR/hosts.backup" /etc/hosts
        log_info "Hosts-Datei wiederhergestellt"
    fi
    
    # WireGuard stoppen und entfernen
    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl disable wg-quick@wg0 2>/dev/null || true
    rm -f /etc/wireguard/wg0.conf
    log_info "WireGuard gestoppt"
    
    log_success "Rollback abgeschlossen!"
    log_warning "Bitte Server neu starten: reboot"
}

# Sicherheitsprüfungen
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "Bitte als root ausführen (sudo ./proxclusterbridge.sh)"
        exit 1
    fi
}

check_proxmox() {
    if ! command -v pvecm &> /dev/null; then
        log_error "Proxmox VE ist nicht installiert!"
        exit 1
    fi
    log_success "Proxmox VE gefunden: $(pveversion)"
}

check_existing_cluster() {
    if pvecm status &>/dev/null; then
        log_warning "Dieser Server ist bereits in einem Cluster!"
        pvecm status
        read -p "Trotzdem fortfahren? (j/n): " response
        if [[ ! $response =~ ^[jJ]$ ]]; then
            log_info "Abgebrochen."
            exit 0
        fi
    fi
}

check_network_connectivity() {
    log_step "Prüfe Netzwerk-Konnektivität..."
    
    if ! ping -c 2 8.8.8.8 &>/dev/null; then
        log_error "Keine Internet-Verbindung!"
        exit 1
    fi
    log_success "Internet-Verbindung OK"
}

check_disk_space() {
    local available=$(df / | awk 'NR==2 {print $4}')
    if [ "$available" -lt 1048576 ]; then  # < 1GB
        log_warning "Weniger als 1GB freier Speicherplatz!"
        read -p "Trotzdem fortfahren? (j/n): " response
        if [[ ! $response =~ ^[jJ]$ ]]; then
            exit 0
        fi
    fi
}

pre_flight_checks() {
    log_step "Führe Sicherheitsprüfungen durch..."
    echo ""
    
    check_root
    check_proxmox
    check_existing_cluster
    check_network_connectivity
    check_disk_space
    
    echo ""
    log_success "Alle Prüfungen bestanden!"
    echo ""
}

# WireGuard Installation
install_wireguard() {
    log_step "Installiere WireGuard..."
    
    read -p "WireGuard installieren? (j/n): " response
    if [[ ! $response =~ ^[jJ]$ ]]; then
        log_info "Übersprungen"
        return
    fi
    
    apt update -qq
    apt install -y wireguard wireguard-tools qrencode
    
    log_success "WireGuard installiert"
}

generate_wireguard_keys() {
    log_step "Generiere WireGuard Keys..."
    
    if [ -f "/etc/wireguard/privatekey" ]; then
        log_warning "Keys existieren bereits!"
        read -p "Neue Keys generieren? (j/n): " response
        if [[ ! $response =~ ^[jJ]$ ]]; then
            return
        fi
        backup_directory "/etc/wireguard"
    fi
    
    mkdir -p /etc/wireguard
    
    WG_PRIVATE_KEY=$(wg genkey)
    WG_PUBLIC_KEY=$(echo "$WG_PRIVATE_KEY" | wg pubkey)
    
    echo "$WG_PRIVATE_KEY" > /etc/wireguard/privatekey
    echo "$WG_PUBLIC_KEY" > /etc/wireguard/publickey
    chmod 600 /etc/wireguard/privatekey
    chmod 644 /etc/wireguard/publickey
    
    log_success "Keys generiert!"
    echo ""
    echo "═══════════════════════════════════════════"
    echo "Public Key (für anderen Server):"
    echo "$WG_PUBLIC_KEY"
    echo "═══════════════════════════════════════════"
    echo ""
}

# Node-Konfiguration
configure_node() {
    clear
    echo "════════════════════════════════════════════════"
    echo "  ProxClusterBridge - Node Konfiguration"
    echo "════════════════════════════════════════════════"
    echo ""
    
    pre_flight_checks
    create_full_backup
    
    read -p "Ist dies der ERSTE Server (Master)? (j/n): " IS_MASTER
    
    if [[ $IS_MASTER =~ ^[jJ]$ ]]; then
        setup_master_node
    else
        setup_worker_node
    fi
}

setup_master_node() {
    log_step "Konfiguriere Master-Node..."
    echo ""
    
    # Informationen sammeln
    CURRENT_HOSTNAME=$(hostname)
    read -p "Neuer Hostname [$CURRENT_HOSTNAME]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-$CURRENT_HOSTNAME}
    
    read -p "WireGuard IP für diesen Server (z.B. 10.99.0.1): " WG_IP
    read -p "Öffentliche IP dieses Servers: " PUBLIC_IP
    read -p "WireGuard Port [51820]: " WG_PORT
    WG_PORT=${WG_PORT:-51820}
    
    echo ""
    log_warning "Folgende Änderungen werden vorgenommen:"
    echo "  - Hostname: $CURRENT_HOSTNAME → $HOSTNAME"
    echo "  - WireGuard IP: $WG_IP"
    echo "  - WireGuard Port: $WG_PORT"
    echo "  - IP Forwarding wird aktiviert"
    echo ""
    
    read -p "Fortfahren? (j/n): " confirm
    if [[ ! $confirm =~ ^[jJ]$ ]]; then
        log_info "Abgebrochen"
        exit 0
    fi
    
    # Hostname setzen
    backup_file "/etc/hostname"
    backup_file "/etc/hosts"
    hostnamectl set-hostname "$HOSTNAME"
    log_success "Hostname gesetzt: $HOSTNAME"
    
    # WireGuard Config erstellen
    log_step "Erstelle WireGuard Konfiguration..."
    
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $WG_IP/24
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Worker-Nodes werden hier hinzugefügt:
# Beispiel:
# [Peer]
# PublicKey = WORKER_PUBLIC_KEY
# AllowedIPs = 10.99.0.2/32
EOF

    chmod 600 /etc/wireguard/wg0.conf
    log_success "WireGuard Config erstellt"
    
    # Firewall konfigurieren
    log_step "Konfiguriere Firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw allow "$WG_PORT"/udp comment "WireGuard ProxClusterBridge"
        log_success "UFW Regel hinzugefügt"
    fi
    
    # IP Forwarding aktivieren
    backup_file "/etc/sysctl.conf"
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -p > /dev/null
    log_success "IP Forwarding aktiviert"
    
    # WireGuard starten
    log_step "Starte WireGuard..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    
    if systemctl is-active --quiet wg-quick@wg0; then
        log_success "WireGuard läuft"
    else
        log_error "WireGuard konnte nicht gestartet werden!"
        log_info "Prüfe: journalctl -u wg-quick@wg0"
        exit 1
    fi
    
    # Proxmox Cluster erstellen
    log_step "Erstelle Proxmox Cluster..."
    read -p "Cluster Name: " CLUSTER_NAME
    
    read -p "Cluster jetzt erstellen? (j/n): " confirm
    if [[ $confirm =~ ^[jJ]$ ]]; then
        pvecm create "$CLUSTER_NAME" --bindnet0_addr="$WG_IP"
        log_success "Cluster '$CLUSTER_NAME' erstellt!"
    else
        log_info "Cluster-Erstellung übersprungen"
        log_warning "Manuell erstellen mit: pvecm create $CLUSTER_NAME --bindnet0_addr=$WG_IP"
    fi
    
    # Zusammenfassung
    echo ""
    echo "════════════════════════════════════════════════"
    echo "  Master-Node erfolgreich konfiguriert!"
    echo "════════════════════════════════════════════════"
    echo ""
    echo "📋 Informationen für Worker-Node:"
    echo "─────────────────────────────────────────────"
    echo "Master Public Key:"
    echo "$(cat /etc/wireguard/publickey)"
    echo ""
    echo "Master WireGuard IP: $WG_IP"
    echo "Master Public IP: $PUBLIC_IP"
    echo "WireGuard Port: $WG_PORT"
    echo ""
    echo "🔧 Nächste Schritte:"
    echo "─────────────────────────────────────────────"
    echo "1. Speichere die obigen Informationen"
    echo "2. Führe dieses Script auf dem Worker-Server aus"
    echo "3. Nach Worker-Setup, füge auf diesem Server hinzu:"
    echo ""
    echo "   # In /etc/wireguard/wg0.conf:"
    echo "   [Peer]"
    echo "   PublicKey = <WORKER_PUBLIC_KEY>"
    echo "   AllowedIPs = <WORKER_WG_IP>/32"
    echo ""
    echo "   # Dann:"
    echo "   systemctl restart wg-quick@wg0"
    echo ""
    echo "💾 Backup gespeichert in:"
    echo "   $BACKUP_DIR"
    echo "════════════════════════════════════════════════"
    echo ""
}

setup_worker_node() {
    log_step "Konfiguriere Worker-Node..."
    echo ""
    
    # Informationen sammeln
    CURRENT_HOSTNAME=$(hostname)
    read -p "Neuer Hostname [$CURRENT_HOSTNAME]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-$CURRENT_HOSTNAME}
    
    read -p "WireGuard IP für diesen Server (z.B. 10.99.0.2): " WG_IP
    
    echo ""
    echo "Informationen vom Master-Server benötigt:"
    read -p "Public Key des Masters: " MASTER_PUBLIC_KEY
    read -p "WireGuard IP des Masters (z.B. 10.99.0.1): " MASTER_WG_IP
    read -p "Öffentliche IP des Masters: " MASTER_PUBLIC_IP
    read -p "WireGuard Port des Masters [51820]: " MASTER_WG_PORT
    MASTER_WG_PORT=${MASTER_WG_PORT:-51820}
    
    echo ""
    log_warning "Folgende Änderungen werden vorgenommen:"
    echo "  - Hostname: $CURRENT_HOSTNAME → $HOSTNAME"
    echo "  - WireGuard IP: $WG_IP"
    echo "  - Verbindung zu Master: $MASTER_PUBLIC_IP:$MASTER_WG_PORT"
    echo ""
    
    read -p "Fortfahren? (j/n): " confirm
    if [[ ! $confirm =~ ^[jJ]$ ]]; then
        log_info "Abgebrochen"
        exit 0
    fi
    
    # Hostname setzen
    backup_file "/etc/hostname"
    backup_file "/etc/hosts"
    hostnamectl set-hostname "$HOSTNAME"
    log_success "Hostname gesetzt: $HOSTNAME"
    
    # WireGuard Config erstellen
    log_step "Erstelle WireGuard Konfiguration..."
    
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $WG_IP/24
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $MASTER_PUBLIC_KEY
Endpoint = $MASTER_PUBLIC_IP:$MASTER_WG_PORT
AllowedIPs = $MASTER_WG_IP/32, 10.99.0.0/24
PersistentKeepalive = 25
EOF

    chmod 600 /etc/wireguard/wg0.conf
    log_success "WireGuard Config erstellt"
    
    # IP Forwarding aktivieren
    backup_file "/etc/sysctl.conf"
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -p > /dev/null
    log_success "IP Forwarding aktiviert"
    
    # WireGuard starten
    log_step "Starte WireGuard..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    
    if systemctl is-active --quiet wg-quick@wg0; then
        log_success "WireGuard läuft"
    else
        log_error "WireGuard konnte nicht gestartet werden!"
        exit 1
    fi
    
    # Verbindung testen
    log_step "Teste Verbindung zum Master..."
    sleep 3
    
    if ping -c 4 -W 2 "$MASTER_WG_IP" &>/dev/null; then
        log_success "Verbindung zum Master erfolgreich!"
    else
        log_error "Keine Verbindung zum Master!"
        log_warning "Mögliche Ursachen:"
        echo "  1. Master-Server hat Worker noch nicht in Config eingetragen"
        echo "  2. Firewall blockiert Verbindung"
        echo "  3. WireGuard läuft nicht auf Master"
        echo ""
        read -p "Trotzdem fortfahren? (j/n): " response
        if [[ ! $response =~ ^[jJ]$ ]]; then
            exit 1
        fi
    fi
    
    # Zusammenfassung für Master
    echo ""
    echo "════════════════════════════════════════════════"
    echo "  Worker-Node Konfiguration abgeschlossen!"
    echo "════════════════════════════════════════════════"
    echo ""
    echo "📋 Diese Informationen auf dem MASTER eintragen:"
    echo "─────────────────────────────────────────────"
    echo ""
    echo "Worker Public Key:"
    echo "$(cat /etc/wireguard/publickey)"
    echo ""
    echo "In /etc/wireguard/wg0.conf auf dem Master:"
    echo ""
    echo "[Peer]"
    echo "PublicKey = $(cat /etc/wireguard/publickey)"
    echo "AllowedIPs = $WG_IP/32"
    echo ""
    echo "Dann auf dem Master:"
    echo "systemctl restart wg-quick@wg0"
    echo ""
    echo "════════════════════════════════════════════════"
    echo ""
    
    read -p "Wurde die Konfiguration auf dem Master eingetragen? (j/n): " master_ready
    
    if [[ ! $master_ready =~ ^[jJ]$ ]]; then
        log_warning "Bitte erst Master konfigurieren, dann fortfahren"
        exit 0
    fi
    
    # Erneut Verbindung testen
    log_step "Teste Verbindung erneut..."
    if ping -c 4 "$MASTER_WG_IP" &>/dev/null; then
        log_success "Verbindung OK!"
    else
        log_error "Immer noch keine Verbindung!"
        exit 1
    fi
    
    # Cluster beitreten
    log_step "Trete dem Cluster bei..."
    log_warning "Root-Passwort des Masters wird benötigt!"
    echo ""
    
    read -p "Jetzt dem Cluster beitreten? (j/n): " confirm
    if [[ $confirm =~ ^[jJ]$ ]]; then
        if pvecm add "$MASTER_WG_IP" --use_ssh; then
            log_success "Erfolgreich dem Cluster beigetreten!"
        else
            log_error "Cluster-Beitritt fehlgeschlagen!"
            log_info "Versuche es manuell: pvecm add $MASTER_WG_IP --use_ssh"
        fi
    else
        log_info "Cluster-Beitritt übersprungen"
        log_warning "Manuell beitreten mit: pvecm add $MASTER_WG_IP --use_ssh"
    fi
    
    echo ""
    echo "════════════════════════════════════════════════"
    echo "  Setup abgeschlossen!"
    echo "════════════════════════════════════════════════"
    echo ""
    echo "💾 Backup gespeichert in:"
    echo "   $BACKUP_DIR"
    echo ""
}

# Test-Funktionen
test_connectivity() {
    log_step "Teste Netzwerk-Verbindung..."
    echo ""
    
    read -p "IP des anderen Nodes: " TEST_IP
    
    echo ""
    log_info "Führe Ping-Test durch..."
    
    if ping -c 4 "$TEST_IP"; then
        echo ""
        log_success "Verbindung erfolgreich!"
    else
        echo ""
        log_error "Verbindung fehlgeschlagen!"
        echo ""
        log_info "Debugging-Schritte:"
        echo "  1. WireGuard Status: wg show"
        echo "  2. Routing-Tabelle: ip route"
        echo "  3. WireGuard Logs: journalctl -u wg-quick@wg0"
        echo "  4. Firewall: iptables -L -n -v"
    fi
}

show_status() {
    clear
    echo "════════════════════════════════════════════════"
    echo "  ProxClusterBridge - System Status"
    echo "════════════════════════════════════════════════"
    echo ""
    
    echo "📡 WireGuard Status:"
    echo "────────────────────────────────────────────────"
    if systemctl is-active --quiet wg-quick@wg0; then
        log_success "WireGuard läuft"
        wg show
    else
        log_error "WireGuard läuft nicht!"
    fi
    
    echo ""
    echo "🔧 Proxmox Cluster Status:"
    echo "────────────────────────────────────────────────"
    if pvecm status &>/dev/null; then
        pvecm status
        echo ""
        echo "Cluster Nodes:"
        pvecm nodes
    else
        log_warning "Nicht in einem Cluster"
    fi
    
    echo ""
    echo "🌐 Netzwerk Interfaces:"
    echo "────────────────────────────────────────────────"
    ip -4 addr show | grep -E 'inet|^[0-9]'
    
    echo ""
    echo "════════════════════════════════════════════════"
}

# Haupt-Menü
main_menu() {
    while true; do
        clear
        echo "════════════════════════════════════════════════"
        echo "  ProxClusterBridge v1.0 - Safe Mode"
        echo "════════════════════════════════════════════════"
        echo ""
        echo "  🚀 Setup & Installation:"
        echo "  1) Vollständiges Setup (Empfohlen)"
        echo "  2) Nur WireGuard installieren"
        echo "  3) Nur WireGuard Keys generieren"
        echo ""
        echo "  🔧 Wartung & Tools:"
        echo "  4) Verbindung testen"
        echo "  5) System-Status anzeigen"
        echo "  6) WireGuard neu starten"
        echo ""
        echo "  ⚠️  Notfall & Rollback:"
        echo "  7) Backup erstellen (manuell)"
        echo "  8) Rollback durchführen"
        echo ""
        echo "  9) Beenden"
        echo ""
        echo "════════════════════════════════════════════════"
        echo ""
        read -p "Wähle eine Option [1-9]: " choice
        
        case $choice in
            1)
                check_root
                install_wireguard
                generate_wireguard_keys
                configure_node
                echo ""
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            2)
                check_root
                check_proxmox
                install_wireguard
                log_success "WireGuard installiert"
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            3)
                check_root
                generate_wireguard_keys
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            4)
                test_connectivity
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            5)
                show_status
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            6)
                check_root
                log_step "Starte WireGuard neu..."
                systemctl restart wg-quick@wg0
                if systemctl is-active --quiet wg-quick@wg0; then
                    log_success "WireGuard neugestartet"
                    wg show
                else
                    log_error "Fehler beim Neustart!"
                fi
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            7)
                check_root
                create_full_backup
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            8)
                check_root
                perform_rollback
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            9)
                echo ""
                log_info "Auf Wiedersehen! 👋"
                echo ""
                exit 0
                ;;
            *)
                log_error "Ungültige Option"
                sleep 1
                ;;
        esac
    done
}

# Zeige Banner
clear
echo "════════════════════════════════════════════════"
echo "  ProxClusterBridge v1.0"
echo "  Safe Multi-Site Proxmox Cluster Setup"
echo "════════════════════════════════════════════════"
echo ""
echo "  🔒 Safe Mode aktiviert:"
echo "     ✓ Automatische Backups"
echo "     ✓ Rollback-Funktion"
echo "     ✓ Bestätigungen bei kritischen Schritten"
echo ""
echo "════════════════════════════════════════════════"
sleep 2

# Script starten
main_menu