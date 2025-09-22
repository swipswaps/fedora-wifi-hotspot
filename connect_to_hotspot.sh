#!/bin/bash
# Script: connect_to_hotspot.sh
# Description: Connects a Linux client to a specified Wi-Fi hotspot, with backup and troubleshooting info.
# Author: Your Name (or AI Assistant)
# Date: 2025-09-22

# --- Configuration Variables ---
LOG_FILE="/var/log/hotspot_client_connect.log"
BACKUP_DIR="/etc/hotspot_client_backup_$(date +%Y%m%d%H%M%S)"
# --- !!! IMPORTANT: Customize these values !!! ---
WIFI_IFACE=""               # e.g., "wlp0s20f3", "wlan0" - WILL BE DETECTED IF EMPTY
HOTSPOT_SSID="MyFedoraHotspot" # MUST match the Fedora hotspot SSID
HOTSPOT_PASSWORD="ChangeMeToAStrongPassword" # MUST match the Fedora hotspot password
HOTSPOT_CONN_NAME="Client Hotspot Connection" # A name for NetworkManager to store this connection profile

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

detect_wifi_interface() {
    log_message "INFO" "Detecting Wi-Fi interface..."
    if [ -z "$WIFI_IFACE" ]; then
        WIFI_IFACE=$(nmcli device status | grep 'wifi' | awk '{print $1}' | head -n 1)
        if [ -z "$WIFI_IFACE" ]; then
            log_message "ERROR" "No Wi-Fi interface detected. Please specify WIFI_IFACE manually in the script."
            exit 1
        else
            log_message "INFO" "Detected Wi-Fi interface: ${WIFI_IFACE}"
        fi
    fi
}

# --- Main Script Logic ---

connect_to_hotspot() {
    log_message "INFO" "Starting Client Wi-Fi Hotspot Connection..."

    # 1. Backup NetworkManager connection profiles if they exist
    log_message "INFO" "Creating backup directory: ${BACKUP_DIR}"
    run_command "sudo mkdir -p ${BACKUP_DIR}"
    # Backup all current nmcli connections
    for conn_uuid in $(nmcli -t -f UUID,TYPE connection show | grep '^.*:wifi$' | cut -d':' -f1); do
        backup_file "/etc/NetworkManager/system-connections/${conn_uuid}.nmconnection"
    done

    # 2. Ensure NetworkManager-wifi is installed
    log_message "INFO" "Ensuring NetworkManager-wifi is installed..."
    run_command "sudo dnf install -y NetworkManager-wifi"

    # 3. Disconnect existing Wi-Fi connection if active on target interface
    if nmcli device show "${WIFI_IFACE}" | grep -q "STATE: connected"; then
        log_message "INFO" "Wi-Fi interface ${WIFI_IFACE} is currently connected. Disconnecting..."
        run_command "sudo nmcli device disconnect \"${WIFI_IFACE}\""
    fi

    # 4. Create/Modify Wi-Fi Connection Profile for the Hotspot
    log_message "INFO" "Creating/modifying NetworkManager connection profile '${HOTSPOT_CONN_NAME}' for SSID '${HOTSPOT_SSID}'..."
    
    # Delete existing connection with the same name if it exists, to ensure a clean slate
    if nmcli connection show "${HOTSPOT_CONN_NAME}" &>/dev/null; then
        log_message "INFO" "Existing connection '${HOTSPOT_CONN_NAME}' found, deleting it first."
        run_command "sudo nmcli connection delete \"${HOTSPOT_CONN_NAME}\""
    fi

    run_command "sudo nmcli connection add type wifi ifname \"${WIFI_IFACE}\" con-name \"${HOTSPOT_CONN_NAME}\" autoconnect yes ssid \"${HOTSPOT_SSID}\""
    run_command "sudo nmcli connection modify \"${HOTSPOT_CONN_NAME}\" wifi-sec.key-mgmt wpa-psk wifi-sec.psk \"${HOTSPOT_PASSWORD}\""
    run_command "sudo nmcli connection modify \"${HOTSPOT_CONN_NAME}\" ipv4.method auto" # Client gets IP via DHCP
    run_command "sudo nmcli connection modify \"${HOTSPOT_CONN_NAME}\" ipv6.method auto" # Client gets IP via DHCP

    # 5. Activate the Connection
    log_message "INFO" "Activating the Wi-Fi connection to '${HOTSPOT_SSID}'..."
    run_command "sudo nmcli connection up \"${HOTSPOT_CONN_NAME}\""
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to activate connection to hotspot. Check logs for details."
        exit 1
    fi

    log_message "INFO" "Waiting for IP address assignment..."
    sleep 10 # Give it some time to get an IP

    log_message "INFO" "Verifying internet access..."
    if ! ping -c 4 google.com &>/dev/null; then
        log_message "ERROR" "Connection to hotspot '${HOTSPOT_SSID}' established, but no internet access detected."
        # Don't exit here, still want to show troubleshooting info
    else
        log_message "INFO" "Internet access confirmed via hotspot."
    fi

    log_message "INFO" "Client Hotspot Connection Complete!"
    echo -e "\n-----------------------------------------------------" | tee -a "${LOG_FILE}"
    echo -e "   Connected to hotspot '${HOTSPOT_SSID}'.            " | tee -a "${LOG_FILE}"
    echo -e "-----------------------------------------------------\n" | tee -a "${LOG_FILE}"
}

# --- Recovery Function ---
recover_settings() {
    log_message "INFO" "Initiating recovery process..."
    if [ -d "${BACKUP_DIR}" ]; then
        log_message "INFO" "Backup found at ${BACKUP_DIR}. You can manually restore connection files:"
        log_message "INFO" "  Examine ${BACKUP_DIR}/etc/NetworkManager/system-connections/ for your old connection profiles."
        log_message "INFO" "  To restore: sudo cp ${BACKUP_DIR}/etc/NetworkManager/system-connections/<old_uuid>.nmconnection /etc/NetworkManager/system-connections/"
        log_message "INFO" "  Then activate: sudo nmcli connection reload && sudo nmcli connection up <old_connection_name_or_uuid>"
        log_message "INFO" "  To remove the hotspot connection: sudo nmcli connection delete \"${HOTSPOT_CONN_NAME}\""
        log_message "INFO" "  Remember to restart NetworkManager (sudo systemctl restart NetworkManager) after manual changes."
    else
        log_message "ERROR" "No backup directory found at ${BACKUP_DIR}. Cannot perform recovery."
    fi
}

# --- Troubleshooting Information Display ---
display_troubleshooting_info() {
    echo -e "\n--- Current System State for Client Troubleshooting ---" | tee -a "${LOG_FILE}"

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

    log_message "INFO" "### 6. DNS Resolution Configuration ###"
    run_command "cat /etc/resolv.conf"

    log_message "INFO" "### 7. Ping Test to Google DNS (8.8.8.8) ###"
    run_command "ping -c 4 8.8.8.8"

    log_message "INFO" "### 8. Ping Test to Google.com ###"
    run_command "ping -c 4 google.com"

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
echo " Client Hotspot Connection Script                    " | tee -a "${LOG_FILE}"
echo "-----------------------------------------------------" | tee -a "${LOG_FILE}"

if [ "$1" == "troubleshoot" ]; then
    log_message "INFO" "Troubleshooting mode requested."
    detect_wifi_interface # Still need to detect interfaces for info display
    display_troubleshooting_info
    exit 0
elif [ "$1" == "recover" ]; then
    log_message "INFO" "Recovery mode requested."
    recover_settings
    exit 0
elif [ "$1" == "reset" ]; then
    log_message "INFO" "Resetting client hotspot connection '${HOTSPOT_CONN_NAME}'..."
    run_command "sudo nmcli connection delete \"${HOTSPOT_CONN_NAME}\""
    log_message "INFO" "Client hotspot connection removed. You may need to manually revert other changes from backups."
    log_message "INFO" "Consider running 'recover' command for more detailed instructions."
    exit 0
fi

detect_wifi_interface
connect_to_hotspot
display_troubleshooting_info