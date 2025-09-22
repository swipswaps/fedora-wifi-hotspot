#!/usr/bin/env bash
# setup_fedora_hotspot_v17.sh
# Full-feature Fedora hotspot script: backups, firewall, ip-forwarding, recovery, and full real-time status
# Version: v17 — single-copy logging + immediate status snapshot + visible commands
# Author: Jose Melendez
# Date: 2025-09-22

set -euo pipefail

# --- Logging setup: line-buffered tee so terminal always shows output immediately and it's appended to the log ---
TIMESTAMP=$(date '+%Y%m%d%H%M%S')
LOG_FILE="/var/log/fedora_hotspot_setup_${TIMESTAMP}.log"
BACKUP_ROOT="/etc/fedora_hotspot_backups"

# Ensure log directory writable
mkdir -p "$(dirname "$LOG_FILE")"
# Route all subsequent stdout/stderr to tee (line-buffered)
exec > >(stdbuf -oL tee -a "$LOG_FILE") 2>&1

# --- Helpers ---
info()  { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  $*"; }
warn()  { echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN]  $*"; }
error() { echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*"; }

# Run a command, print it, capture status and print success/failure
run() {
    echo
    echo ">>> $*"
    if "$@"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [OK]   $*"
        return 0
    else
        rc=$?
        echo "$(date '+%Y-%m-%d %H:%M:%S') [FAIL] ($rc) $*"
        return $rc
    fi
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root. Use: sudo $0"
        exit 1
    fi
}

# --- Interface detection & backup setup ---
WIFI_IFACE="${WIFI_IFACE:-}"
ETH_IFACE="${ETH_IFACE:-}"

detect_interfaces() {
    info "Detecting network interfaces..."
    if [ -z "$WIFI_IFACE" ]; then
        WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '/:wifi$/ {print $1; exit}')
    fi
    if [ -z "$WIFI_IFACE" ]; then
        error "No Wi-Fi interface found. Export WIFI_IFACE or attach a Wi-Fi device."
        exit 1
    fi
    info "Wi-Fi interface: $WIFI_IFACE"

    if [ -z "$ETH_IFACE" ]; then
        ETH_IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '/:ethernet$/ {print $1; exit}')
        if [ -z "$ETH_IFACE" ]; then
            ETH_IFACE=$(ip route | awk '/default/ {print $5; exit}')
        fi
    fi
    if [ -n "$ETH_IFACE" ]; then
        info "Uplink/interface with default route: $ETH_IFACE"
    else
        warn "No uplink interface detected. Hotspot will work locally but may not share internet."
    fi
}

create_backup_dir() {
    mkdir -p "$BACKUP_ROOT"
    BACKUP_DIR="${BACKUP_ROOT}/backup_${TIMESTAMP}"
    mkdir -p "$BACKUP_DIR"
    info "Created backup directory: $BACKUP_DIR"
}

backup_files() {
    info "Backing up relevant files..."
    if [ -f /etc/sysctl.conf ]; then
        run cp -p /etc/sysctl.conf "${BACKUP_DIR}/sysctl.conf"
    else
        warn "/etc/sysctl.conf not found; skipping"
    fi

    if [ -d /etc/NetworkManager/system-connections ]; then
        run mkdir -p "${BACKUP_DIR}/system-connections"
        # Copy only files (if any); ignore errors
        run cp -p /etc/NetworkManager/system-connections/* "${BACKUP_DIR}/system-connections/" || true
    else
        warn "No /etc/NetworkManager/system-connections directory found; skipping"
    fi

    if [ -f /etc/firewalld/zones/public.xml ]; then
        run cp -p /etc/firewalld/zones/public.xml "${BACKUP_DIR}/public.xml"
    else
        warn "No /etc/firewalld/zones/public.xml found; skipping"
    fi
}

# --- Interactive prompts ---
prompt_info() {
    echo
    read -rp "Enter Hotspot SSID [FedoraHotspot]: " HOTSPOT_SSID
    HOTSPOT_SSID=${HOTSPOT_SSID:-FedoraHotspot}

    read -rp "Enter Hotspot connection name [fedora_hotspot]: " HOTSPOT_CONN
    HOTSPOT_CONN=${HOTSPOT_CONN:-fedora_hotspot}

    # Hidden password prompt (script runs as root)
    read -rsp "Enter Hotspot password (min 8 chars): " HOTSPOT_PASS
    echo
    if [ "${#HOTSPOT_PASS}" -lt 8 ]; then
        warn "Password is shorter than 8 characters; WPA2 usually requires >= 8."
    fi

    info "Parameters: SSID='$HOTSPOT_SSID', Connection='$HOTSPOT_CONN', Wi-Fi interface='$WIFI_IFACE'"
}

# --- Package / sysctl / firewall ---
ensure_packages() {
    info "Installing or verifying required packages..."
    # Don't fail hard on dnf errors; log and continue (user can inspect log)
    if ! dnf install -y NetworkManager-wifi network-manager-applet firewalld; then
        warn "dnf reported an issue installing packages — check $LOG_FILE"
    fi
}

enable_ip_forwarding() {
    info "Ensuring IP forwarding is enabled in /etc/sysctl.conf"
    if ! grep -qE '^\s*net.ipv4.ip_forward\s*=\s*1' /etc/sysctl.conf 2>/dev/null; then
        echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
        info "Appended net.ipv4.ip_forward = 1"
    else
        info "net.ipv4.ip_forward already present"
    fi

    if ! grep -qE '^\s*net.ipv6.conf.all.forwarding\s*=\s*1' /etc/sysctl.conf 2>/dev/null; then
        echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
        info "Appended net.ipv6.conf.all.forwarding = 1"
    else
        info "net.ipv6.conf.all.forwarding already present"
    fi

    run sysctl -p
}

configure_firewall() {
    info "Enabling and starting firewalld..."
    run systemctl enable --now firewalld || warn "firewalld start failed (check logs)"

    # Choose zone for uplink interface; fallback to 'public'
    if [ -n "$ETH_IFACE" ]; then
        ZONE=$(firewall-cmd --get-zone-of-interface="$ETH_IFACE" 2>/dev/null || echo public)
    else
        ZONE=public
    fi
    info "Using firewall zone: $ZONE (for interface: ${ETH_IFACE:-none})"

    run firewall-cmd --zone="$ZONE" --add-masquerade --permanent || warn "Could not add masquerade to $ZONE"
    run firewall-cmd --reload || warn "firewall-cmd --reload failed"
}

# --- Hotspot creation + activation with retries & visible progress ---
create_and_activate_hotspot() {
    info "Removing existing connection named '$HOTSPOT_CONN' (if exists)"
    nmcli connection delete "$HOTSPOT_CONN" 2>/dev/null || true

    info "Unblocking Wi-Fi and preparing interface"
    run rfkill unblock wifi || true
    run nmcli device set "$WIFI_IFACE" managed no || true
    run ip link set "$WIFI_IFACE" down || true
    sleep 1

    info "Adding hotspot connection in AP mode (mode=ap)"
    run nmcli connection add type wifi ifname "$WIFI_IFACE" con-name "$HOTSPOT_CONN" ssid "$HOTSPOT_SSID" mode ap

    info "Configuring hotspot security and IP"
    run nmcli connection modify "$HOTSPOT_CONN" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PASS"
    run nmcli connection modify "$HOTSPOT_CONN" ipv4.method shared ipv6.method ignore autoconnect yes

    info "Returning interface control to NetworkManager and attempting activation"
    run nmcli device set "$WIFI_IFACE" managed yes
    sleep 1

    # Activation loop with a visible timeout
    MAX_WAIT=30
    ELAPSED=0
    while :; do
        info "Attempting to bring connection up (elapsed ${ELAPSED}s)..."
        if nmcli connection up "$HOTSPOT_CONN" 2>&1 | tee -a "$LOG_FILE"; then
            info "Connection '$HOTSPOT_CONN' activated successfully"
            break
        else
            warn "Activation attempt failed; will retry"
        fi
        sleep 2
        ELAPSED=$((ELAPSED+2))
        if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
            error "Failed to activate hotspot after ${MAX_WAIT}s"
            info "Tail of NetworkManager journal to help debugging:"
            journalctl -u NetworkManager -n 50 --no-pager | tee -a "$LOG_FILE"
            exit 1
        fi
    done
}

# --- Status snapshot (printed after activation) ---
show_status_snapshot() {
    info "==== STATUS SNAPSHOT START ===="
    run nmcli device status
    run nmcli connection show --active
    run nmcli -f all connection show "$HOTSPOT_CONN" || true
    run ip -4 addr show "$WIFI_IFACE" || true
    run ip -4 route show || true
    info "IP forwarding:"
    run sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding || true
    info "Firewalld zones and settings:"
    run firewall-cmd --get-active-zones || true
    ZONE=$(firewall-cmd --get-zone-of-interface="$ETH_IFACE" 2>/dev/null || echo public)
    info "Zone for uplink ($ETH_IFACE): $ZONE"
    run firewall-cmd --zone="$ZONE" --list-all || true
    run rfkill list || true
    info "Last 50 lines of NetworkManager journal:"
    run journalctl -u NetworkManager -n 50 --no-pager || true
    info "==== STATUS SNAPSHOT END ===="
}

# --- Recovery (restore the latest backup if any) ---
recover_latest_backup() {
    if [ ! -d "$BACKUP_ROOT" ]; then
        error "No backups directory ($BACKUP_ROOT) exists"
        return 1
    fi
    latest=$(ls -1dt "${BACKUP_ROOT}"/backup_* 2>/dev/null | head -n1 || true)
    if [ -z "$latest" ]; then
        error "No backup runs found under $BACKUP_ROOT"
        return 1
    fi
    info "Restoring from backup: $latest"
    if [ -f "$latest/sysctl.conf" ]; then
        run cp -p "$latest/sysctl.conf" /etc/sysctl.conf
        run sysctl -p
    fi
    if [ -d "$latest/system-connections" ]; then
        info "Restoring NetworkManager connections (may require credentials to be fixed)"
        run cp -p "$latest/system-connections/"* /etc/NetworkManager/system-connections/ || true
        run chmod 600 /etc/NetworkManager/system-connections/* || true
        run nmcli connection reload || true
    fi
    info "Recover complete. Use 'verify' to inspect system state."
}

verify() {
    show_status_snapshot
}

# --- Main flow ---
require_root
create_backup_dir
detect_interfaces

case "${1:-}" in
    recover)
        recover_latest_backup
        ;;
    verify)
        verify
        ;;
    reset)
        read -rp "Connection name to delete [fedora_hotspot]: " xcn
        xcn=${xcn:-fedora_hotspot}
        run nmcli connection delete "$xcn" || true
        info "Deleted connection $xcn (if present)"
        ;;
    *)
        prompt_info
        backup_files
        ensure_packages
        enable_ip_forwarding
        configure_firewall
        create_and_activate_hotspot
        show_status_snapshot
        info "Hotspot '${HOTSPOT_SSID}' should be active. Log: ${LOG_FILE}"
        ;;
esac

exit 0
