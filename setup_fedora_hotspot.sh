#!/bin/bash
# Script: setup_fedora_hotspot.sh
# Description: Automates Wi-Fi hotspot setup on Fedora, with backup, logging, and troubleshooting info.
# Author: Your Name (or AI Assistant)
# Date: 2025-09-22

# --- Configuration Variables ---
LOG_FILE="/var/log/fedora_hotspot_setup.log"
BACKUP_DIR="/etc/fedora_hotspot_backup_$(date +%Y%m%d%H%M%S)"
# --- !!! IMPORTANT: Customize these values !!! ---
WIFI_IFACE=""               # e.g., "wlp0s20f3", "wlan0" - WILL BE DETECTED IF EMPTY
HOTSPOT_SSID="MyFedoraHotspot"
HOTSPOT_PASSWORD="ChangeMeToAStrongPassword" # Min 8 chars for WPA2
HOTSPOT_CONN_NAME="Fedora Hotspot Auto"
ETHERNET_IFACE=""           # e.g., "enp0s3", "eth0" - WILL BE DETECTED IF EMPTY

# --- Functions ---

log_message() {
    local type="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$type] $message" | tee -a "${LOG_FILE}"
}

run_command() {
    local cmd="$1"
    log_message "COMMAND" "${cmd}"
    eval "${cmd}" 2>&1 | tee -a "${LOG_FILE}"
    local status="${PIPESTATUS[0]}"
    if [ "$status" -ne 0 ]; then
        log_message "ERROR" "Command failed with status $status: ${cmd}"
        return "$status"
    fi
    return 0
}

backup_file() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        log_message "INFO" "Backing up ${file_path} to ${BACKUP_DIR}..."
        run_command "sudo mkdir -p ${BACKUP_DIR}/$(dirname ${file_path})"
        run_command "sudo cp -p ${file_path} ${BACKUP_DIR}/$(dirname ${file_path})"
    else
        log_message "WARN" "File not found for backup: ${file_path}"
    fi
}

# --- Pre-flight Checks and Variable Detection ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "This script must be run as root. Please use 'sudo $0'."
        exit 1
    fi
}

detect_interfaces() {
    log_message "INFO" "Detecting network interfaces..."

    if [ -z "$WIFI_IFACE" ]; then
        WIFI_IFACE=$(nmcli device status | grep 'wifi' | awk '{print $1}' | head -n 1)
        if [ -z "$WIFI_IFACE" ]; then
            log_message "ERROR" "No Wi-Fi interface detected. Please specify WIFI_IFACE manually in the script."
            exit 1
        else
            log_message "INFO" "Detected Wi-Fi interface: ${WIFI_IFACE}"
        fi
    fi

    if [ -z "$ETHERNET_IFACE" ]; then
        ETHERNET_IFACE=$(nmcli device status | grep 'ethernet' | awk '{print $1}' | head -n 1)
        if [ -z "$ETHERNET_IFACE" ]; then
            log_message "WARN" "No Ethernet interface detected automatically. Hotspot may not share internet without it."
            log_message "INFO" "Attempting to find an active internet-facing interface..."
            # Fallback to an interface with a default route
            ETHERNET_IFACE=$(ip -4 route show default | awk '{print $5}' | head -n 1)
            if [ -z "$ETHERNET_IFACE" ]; then
                log_message "ERROR" "Could not automatically detect an active internet-facing interface. Please specify ETHERNET_IFACE manually."
                exit 1
            else
                log_message "INFO" "Detected internet-facing interface via default route: ${ETHERNET_IFACE}"
            fi
        else
            log_message "INFO" "Detected Ethernet interface: ${ETHERNET_IFACE}"
        fi
    fi
}

check_internet_access() {
    log_message "INFO" "Verifying internet access via ${ETHERNET_IFACE}..."
    if ! ping -c 4 -I "${ETHERNET_IFACE}" google.com &>/dev/null; then
        log_message "ERROR" "No internet access detected on ${ETHERNET_IFACE}. Please fix your primary internet connection before proceeding."
        exit 1
    else
        log_message "INFO" "Internet access confirmed via ${ETHERNET_IFACE}."
    fi
}

# --- Main Script Logic ---

setup_hotspot() {
    log_message "INFO" "Starting Fedora Wi-Fi Hotspot Setup..."

    # 1. Backup relevant configuration files
    log_message "INFO" "Creating backup directory: ${BACKUP_DIR}"
    run_command "sudo mkdir -p ${BACKUP_DIR}"
    backup_file "/etc/sysctl.conf"
    backup_file "/etc/firewalld/zones/${ETHERNET_IFACE}.xml" # May not exist, but good to check
    backup_file "/etc/firewalld/zones/public.xml"
    backup_file "/etc/NetworkManager/conf.d/10-globally-managed-devices.conf" # If exists

    # 2. Install essential packages
    log_message "INFO" "Ensuring essential packages are installed..."
    run_command "sudo dnf install -y NetworkManager-wifi network-manager-applet"

    # 3. Create/Modify Wi-Fi Hotspot Connection Profile
    log_message "INFO" "Creating/modifying NetworkManager hotspot connection profile '${HOTSPOT_CONN_NAME}'..."
    # Delete existing connection with the same name if it exists, to ensure a clean slate
    if nmcli connection show "${HOTSPOT_CONN_NAME}" &>/dev/null; then
        log_message "INFO" "Existing connection '${HOTSPOT_CONN_NAME}' found, deleting it first."
        run_command "sudo nmcli connection delete \"${HOTSPOT_CONN_NAME}\""
    fi

    # Create the connection
    run_command "sudo nmcli connection add type wifi ifname \"${WIFI_IFACE}\" con-name \"${HOTSPOT_CONN_NAME}\" autoconnect yes ssid \"${HOTSPOT_SSID}\""
    run_command "sudo nmcli connection modify \"${HOTSPOT_CONN_NAME}\" wifi-sec.key-mgmt wpa-psk wifi-sec.psk \"${HOTSPOT_PASSWORD}\""
    run_command "sudo nmcli connection modify \"${HOTSPOT_CONN_NAME}\" ipv4.method shared"
    run_command "sudo nmcli connection modify \"${HOTSPOT_CONN_NAME}\" ipv6.method shared" # Optional, but good practice

    # 4. Enable IP Forwarding
    log_message "INFO" "Enabling IP forwarding..."
    if ! grep -q "^net.ipv4.ip_forward = 1" "/etc/sysctl.conf"; then
        log_message "INFO" "Adding 'net.ipv4.ip_forward = 1' to /etc/sysctl.conf"
        run_command "echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf"
    else
        log_message "INFO" "'net.ipv4.ip_forward = 1' already present in /etc/sysctl.conf"
    fi
    if ! grep -q "^net.ipv6.conf.all.forwarding = 1" "/etc/sysctl.conf"; then
        log_message "INFO" "Adding 'net.ipv6.conf.all.forwarding = 1' to /etc/sysctl.conf"
        run_command "echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf"
    else
        log_message "INFO" "'net.ipv6.conf.all.forwarding = 1' already present in /etc/sysctl.conf"
    fi
    run_command "sudo sysctl -p"

    # 5. Firewall Configuration (NetworkManager handles most, but verify)
    log_message "INFO" "Verifying Firewalld configuration..."
    # Get the zone of the internet-facing interface
    ETHERNET_ZONE=$(sudo firewall-cmd --get-active-zones | grep "${ETHERNET_IFACE}" | awk '{print $1}' | head -n 1)
    if [ -z "$ETHERNET_ZONE" ]; then
        log_message "WARN" "Could not determine Firewalld zone for ${ETHERNET_IFACE}. Defaulting to 'public'."
        ETHERNET_ZONE="public"
    else
        log_message "INFO" "Ethernet interface '${ETHERNET_IFACE}' is in Firewalld zone: ${ETHERNET_ZONE}"
    fi

    if ! sudo firewall-cmd --zone="${ETHERNET_ZONE}" --query-masquerade &>/dev/null; then
        log_message "INFO" "Enabling masquerading for zone '${ETHERNET_ZONE}'..."
        run_command "sudo firewall-cmd --zone=\"${ETHERNET_ZONE}\" --add-masquerade --permanent"
        run_command "sudo firewall-cmd --reload"
    else
        log_message "INFO" "Masquerading already enabled for zone '${ETHERNET_ZONE}'."
    fi

    # 6. Activate the Hotspot
    log_message "INFO" "Activating the hotspot connection '${HOTSPOT_CONN_NAME}'..."
    run_command "sudo nmcli connection up \"${HOTSPOT_CONN_NAME}\""
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to activate hotspot. Check logs for details."
        exit 1
    fi

    log_message "INFO" "Wi-Fi Hotspot Setup Complete!"
    log_message "INFO" "SSID: ${HOTSPOT_SSID}"
    log_message "INFO" "Password: ${HOTSPOT_PASSWORD}"
    log_message "INFO" "Hotspot Gateway IP: Typically 10.42.0.1 (check 'ip a show ${WIFI_IFACE}')"
    echo -e "\n-----------------------------------------------------" | tee -a "${LOG_FILE}"
    echo -e "   Hotspot '${HOTSPOT_SSID}' should now be active.    " | tee -a "${LOG_FILE}"
    echo -e "   Connect your devices using the password provided.   " | tee -a "${LOG_FILE}"
    echo -e "-----------------------------------------------------\n" | tee -a "${LOG_FILE}"
}

# --- Recovery Function ---
# Note: Recovery is best done manually with the backup files.
# This function primarily provides instructions.
recover_settings() {
    log_message "INFO" "Initiating recovery process..."
    if [ -d "${BACKUP_DIR}" ]; then
        log_message "INFO" "Backup found at ${BACKUP_DIR}. You can restore files manually:"
        log_message "INFO" "  sudo cp ${BACKUP_DIR}/etc/sysctl.conf /etc/sysctl.conf"
        log_message "INFO" "  sudo sysctl -p"
        log_message "INFO" "  For Firewalld, examine ${BACKUP_DIR}/etc/firewalld/zones/ and restore specific settings."
        log_message "INFO" "  To remove the hotspot connection: sudo nmcli connection delete \"${HOTSPOT_CONN_NAME}\""
        log_message "INFO" "  Remember to restart services like NetworkManager (sudo systemctl restart NetworkManager) and Firewalld (sudo systemctl restart firewalld) after manual changes."
    else
        log_message "ERROR" "No backup directory found at ${BACKUP_DIR}. Cannot perform recovery."
    fi
}

# --- Troubleshooting Information Display ---
display_troubleshooting_info() {
    echo -e "\n--- Current System State for Troubleshooting ---" | tee -a "${LOG_FILE}"

    log_message "INFO" "### 1. NetworkManager Device Status ###"
    run_command "nmcli device status"

    log_message "INFO" "### 2. NetworkManager Connection List (Active) ###"
    run_command "nmcli connection show --active"

    log_message "INFO" "### 3. Hotspot Connection Details (${HOTSPOT_CONN_NAME}) ###"
    run_command "nmcli connection show \"${HOTSPOT_CONN_NAME}\""

    log_message "INFO" "### 4. IP Addresses and Interfaces ###"
    run_command "ip a"

    log_message "INFO" "### 5. IP Routing Table ###"
    run_command "ip r"

    log_message "INFO" "### 6. IP Forwarding Status ###"
    run_command "sysctl net.ipv4.ip_forward"
    run_command "sysctl net.ipv6.conf.all.forwarding"

    log_message "INFO" "### 7. Firewalld Active Zones ###"
    run_command "sudo firewall-cmd --get-active-zones"

    log_message "INFO" "### 8. Firewalld Masquerading Status (for ${ETHERNET_IFACE}'s zone) ###"
    ETHERNET_ZONE=$(sudo firewall-cmd --get-active-zones | grep "${ETHERNET_IFACE}" | awk '{print $1}' | head -n 1)
    if [ -z "$ETHERNET_ZONE" ]; then
        ETHERNET_ZONE="public" # Fallback
    fi
    run_command "sudo firewall-cmd --zone=${ETHERNET_ZONE} --query-masquerade"
    run_command "sudo firewall-cmd --list-all-zones"

    log_message "INFO" "### 9. RFKill Status ###"
    run_command "rfkill list"

    log_message "INFO" "### 10. Last 50 Lines of NetworkManager Journal ###"
    run_command "sudo journalctl -u NetworkManager --since \"30 minutes ago\" -n 50 --no-pager"

    log_message "INFO" "### 11. Dmesg (Wi-Fi related errors) ###"
    run_command "dmesg | grep -i 'wifi\\|wlan\\|firmware\\|brcm\\|ath\\|iwlwifi\\|rtlwifi'"

    echo -e "\n--- End of Troubleshooting Info ---" | tee -a "${LOG_FILE}"
    echo "Full log available at: ${LOG_FILE}" | tee -a "${LOG_FILE}"
    echo "Backup created at: ${BACKUP_DIR}" | tee -a "${LOG_FILE}"
}

# --- Script Execution ---

check_root

echo "-----------------------------------------------------" | tee -a "${LOG_FILE}"
echo " Fedora Wi-Fi Hotspot Setup Script                   " | tee -a "${LOG_FILE}"
echo "-----------------------------------------------------" | tee -a "${LOG_FILE}"

if [ "$1" == "troubleshoot" ]; then
    log_message "INFO" "Troubleshooting mode requested."
    detect_interfaces # Still need to detect interfaces for info display
    display_troubleshooting_info
    exit 0
elif [ "$1" == "recover" ]; then
    log_message "INFO" "Recovery mode requested."
    recover_settings
    exit 0
elif [ "$1" == "reset" ]; then
    log_message "INFO" "Resetting hotspot connection '${HOTSPOT_CONN_NAME}'..."
    run_command "sudo nmcli connection delete \"${HOTSPOT_CONN_NAME}\""
    log_message "INFO" "Hotspot connection removed. You may need to manually revert other changes from backups."
    log_message "INFO" "Consider running 'recover' command for more detailed instructions."
    exit 0
fi

detect_interfaces
check_internet_access
setup_hotspot
display_troubleshooting_info