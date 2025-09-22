#!/bin/bash
# Script: setup_fedora_hotspot.sh
# Description: Automates Wi-Fi hotspot setup on Fedora with backup, logging, and troubleshooting.
# Author: Jose Melendez
# Date: 2025-09-22
# Source: Fedora Docs, NetworkManager Reference, GitHub community scripts

set -euo pipefail

# --- Configuration ---
LOG_FILE="/var/log/fedora_hotspot_setup.log"
BACKUP_DIR="/etc/fedora_hotspot_backup"
WIFI_IFACE=""                   # Will be auto-detected
ETHERNET_IFACE=""               # Will be auto-detected
HOTSPOT_SSID="${HOTSPOT_SSID:-FedoraHotspot}"
HOTSPOT_PASSWORD="${HOTSPOT_PASSWORD:-ChangeMe123!}" # Do not log this
HOTSPOT_CONN_NAME="${HOTSPOT_CONN_NAME:-fedora_hotspot}"

# --- Utilities ---
log_message() {
    local type="$1"; shift
    local msg="$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$type] $msg" | tee -a "$LOG_FILE"
}

run_command() {
    "$@" 2>&1 | tee -a "$LOG_FILE"
}

backup_file() {
    local f="$1"
    if [[ -f "$f" ]]; then
        local dest="$BACKUP_DIR$(dirname "$f")"
        mkdir -p "$dest"
        cp -p "$f" "$dest/"
        log_message INFO "Backed up $f -> $dest/"
    fi
}

# --- Pre-flight ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Use: sudo $0"
        exit 1
    fi
}

detect_interfaces() {
    log_message INFO "Detecting interfaces..."
    WIFI_IFACE=${WIFI_IFACE:-$(nmcli -t -f DEVICE,TYPE device status | grep ':wifi' | cut -d: -f1 | head -n1)}
    [[ -z "$WIFI_IFACE" ]] && { log_message ERROR "No Wi-Fi interface found"; exit 1; }
    log_message INFO "Wi-Fi: $WIFI_IFACE"

    ETHERNET_IFACE=${ETHERNET_IFACE:-$(nmcli -t -f DEVICE,TYPE device status | grep ':ethernet' | cut -d: -f1 | head -n1)}
    if [[ -z "$ETHERNET_IFACE" ]]; then
        ETHERNET_IFACE=$(ip route | awk '/default/ {print $5; exit}')
    fi
    [[ -z "$ETHERNET_IFACE" ]] && { log_message ERROR "No uplink interface detected"; exit 1; }
    log_message INFO "Uplink: $ETHERNET_IFACE"
}

check_internet() {
    log_message INFO "Checking internet connectivity..."
    if ! curl -s --max-time 5 https://example.com >/dev/null; then
        log_message WARN "Internet check failed; hotspot may not share internet."
    else
        log_message INFO "Internet connectivity OK"
    fi
}

# --- Setup ---
setup_hotspot() {
    log_message INFO "Setting up hotspot..."

    mkdir -p "$BACKUP_DIR"
    backup_file /etc/sysctl.conf
    backup_file /etc/NetworkManager/system-connections

    dnf install -y NetworkManager-wifi network-manager-applet firewalld

    nmcli connection delete "$HOTSPOT_CONN_NAME" 2>/dev/null || true
    nmcli connection add type wifi ifname "$WIFI_IFACE" con-name "$HOTSPOT_CONN_NAME" ssid "$HOTSPOT_SSID"
    nmcli connection modify "$HOTSPOT_CONN_NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PASSWORD"
    nmcli connection modify "$HOTSPOT_CONN_NAME" ipv4.method shared ipv6.method ignore

    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
    sysctl -p

    systemctl enable --now firewalld
    ZONE=$(firewall-cmd --get-zone-of-interface="$ETHERNET_IFACE" || echo public)
    firewall-cmd --zone="$ZONE" --add-masquerade --permanent
    firewall-cmd --reload

    nmcli connection up "$HOTSPOT_CONN_NAME"

    log_message INFO "Hotspot active. SSID: $HOTSPOT_SSID"
    log_message INFO "Password stored securely (not logged)."
}

# --- Recovery ---
recover() {
    if [[ -d "$BACKUP_DIR" ]]; then
        log_message INFO "Restoring sysctl.conf..."
        cp "$BACKUP_DIR/etc/sysctl.conf" /etc/sysctl.conf
        sysctl -p
        log_message INFO "Manual restore of NetworkManager/firewalld configs may be needed."
    else
        log_message ERROR "No backup found."
    fi
}

# --- Troubleshooting ---
troubleshoot() {
    nmcli device status
    nmcli connection show --active
    ip a
    ip r
    sysctl net.ipv4.ip_forward
    firewall-cmd --get-active-zones
    rfkill list
}

# --- Main ---
check_root
case "${1:-}" in
    recover) recover ;;
    troubleshoot) troubleshoot ;;
    reset) nmcli connection delete "$HOTSPOT_CONN_NAME" ;;
    *) detect_interfaces; check_internet; setup_hotspot; troubleshoot ;;
esac
