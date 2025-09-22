# Fedora Wi-Fi Hotspot & Client Connection Scripts

This repository contains two Bash scripts designed to automate the process of setting up a Wi-Fi hotspot on a Fedora system (sharing an Ethernet connection) and connecting a client Linux machine to that hotspot. Both scripts include robust logging, backup mechanisms, and detailed troubleshooting information to help diagnose common issues.

## Table of Contents

1.  [Overview](#overview)
2.  [Prerequisites](#prerequisites)
3.  [Script Descriptions](#script-descriptions)
    *   [`setup_fedora_hotspot.sh`](#setup_fedora_hotspotsh)
    *   [`connect_to_hotspot.sh`](#connect_to_hotspotsh)
4.  [Usage Guide](#usage-guide)
    *   [Step 1: Clone the Repository](#step-1-clone-the-repository)
    *   [Step 2: Customize Configuration Variables](#step-2-customize-configuration-variables)
    *   [Step 3: Run the Fedora Hotspot Setup Script](#step-3-run-the-fedora-hotspot-setup-script)
    *   [Step 4: Run the Client Connection Script](#step-4-run-the-client-connection-script)
5.  [Troubleshooting](#troubleshooting)
    *   [General Troubleshooting Steps](#general-troubleshooting-steps)
    *   [Using the `troubleshoot` option](#using-the-troubleshoot-option)
    *   [Using the `recover` option](#using-the-recover-option)
    *   [Using the `reset` option](#using-the-reset-option)
6.  [License](#license)

---

## 1. Overview

This project provides an automated approach to create a Wi-Fi hotspot on Fedora, allowing other devices to share its internet connection (assumed to be Ethernet-based). It also includes a complementary script for Linux clients to easily connect to this hotspot. The scripts prioritize safety by creating backups and offering detailed diagnostic output.

**Key Features:**

*   **Automation:** Streamlines the configuration of NetworkManager, `sysctl`, and `firewalld`.
*   **Backup & Recovery:** Automatically backs up critical configuration files before making changes. Provides instructions for manual recovery.
*   **Logging:** All actions and output are logged to a dedicated file (`/var/log/fedora_hotspot_setup.log` and `/var/log/hotspot_client_connect.log`).
*   **Troubleshooting:** Generates a comprehensive summary of network settings and logs to assist in diagnosing connection issues.
*   **Idempotent:** The scripts are designed to be run multiple times; they will attempt to set the correct state without necessarily duplicating configurations.

## 2. Prerequisites

### For the Fedora Hotspot Machine:

*   **Operating System:** Fedora 42 (or similar recent Fedora/RHEL-based distribution)
*   **Internet Connection:** A working Ethernet connection (`ethernet` type) providing internet access.
*   **Wi-Fi Adapter:** A functional Wi-Fi adapter (`wifi` type) that supports access point (AP) mode.
*   **Privileges:** `sudo` access.
*   **Packages:** `NetworkManager`, `NetworkManager-wifi`, `network-manager-applet`, `firewalld` (all typically pre-installed on Fedora Workstation).

### For the Client Linux Machine:

*   **Operating System:** Any Linux distribution with `NetworkManager` installed (e.g., Fedora, Ubuntu, Debian).
*   **Wi-Fi Adapter:** A functional Wi-Fi adapter.
*   **Privileges:** `sudo` access.
*   **Packages:** `NetworkManager`, `NetworkManager-wifi`.

## 3. Script Descriptions

### `setup_fedora_hotspot.sh`

This script configures your Fedora machine to act as a Wi-Fi hotspot, sharing its Ethernet internet connection.

*   **Automatic Interface Detection:** Attempts to detect your Wi-Fi (`WIFI_IFACE`) and Ethernet (`ETHERNET_IFACE`) interfaces.
*   **Package Installation:** Ensures `NetworkManager-wifi` and `network-manager-applet` are installed.
*   **NetworkManager Configuration:** Creates a new NetworkManager connection profile for the hotspot, sets it to `shared` mode (which enables NAT/Masquerading and DHCP), and secures it with WPA2.
*   **IP Forwarding:** Ensures `net.ipv4.ip_forward = 1` and `net.ipv6.conf.all.forwarding = 1` are set in `/etc/sysctl.conf` and applied.
*   **Firewalld Integration:** Verifies that masquerading is enabled on the Firewalld zone associated with your Ethernet interface.
*   **Hotspot Activation:** Activates the newly created hotspot connection.
*   **Backup:** Backs up `/etc/sysctl.conf` and relevant `firewalld` and `NetworkManager` connection files.
*   **Logging:** All output is logged to `/var/log/fedora_hotspot_setup.log` and displayed in the terminal.
*   **Troubleshooting Output:** Gathers extensive network and system diagnostics at the end of the run.

### `connect_to_hotspot.sh`

This script connects a client Linux machine to the Wi-Fi hotspot created by the Fedora machine.

*   **Automatic Wi-Fi Interface Detection:** Attempts to detect your client's Wi-Fi interface (`WIFI_IFACE`).
*   **Package Installation:** Ensures `NetworkManager-wifi` is installed.
*   **NetworkManager Configuration:** Creates a new NetworkManager connection profile to connect to the specified SSID with the given password. Sets IPv4/IPv6 methods to `auto` for DHCP.
*   **Connection Activation:** Activates the Wi-Fi connection to the hotspot.
*   **Internet Verification:** Performs a ping test to confirm internet access after connecting.
*   **Backup:** Backs up existing NetworkManager connection profiles.
*   **Logging:** All output is logged to `/var/log/hotspot_client_connect.log` and displayed in the terminal.
*   **Troubleshooting Output:** Gathers extensive network and system diagnostics at the end of the run.

## 4. Usage Guide

### Step 1: Clone the Repository

On **both** your Fedora hotspot machine and your client Linux machine, open a terminal and clone this repository:

```bash
git clone https://github.com/swipswaps/fedora-wifi-hotspot.git
cd fedora-wifi-hotspot
Step 2: Customize Configuration Variables

Before running either script, you must edit the configuration variables at the top of each script to match your environment.
For setup_fedora_hotspot.sh (on Fedora machine):

Open the script in a text editor:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
nano setup_fedora_hotspot.sh

  

Adjust these lines:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
# --- !!! IMPORTANT: Customize these values !!! ---
WIFI_IFACE=""               # e.g., "wlp0s20f3", "wlan0" - LEAVE EMPTY TO AUTO-DETECT, OR SPECIFY
HOTSPOT_SSID="MyFedoraHotspot" # Choose a unique name for your hotspot
HOTSPOT_PASSWORD="YourVerySecurePassword" # **CHANGE THIS! Must be at least 8 characters for WPA2.**
HOTSPOT_CONN_NAME="Fedora Hotspot Auto" # A name for NetworkManager to store this connection profile
ETHERNET_IFACE=""           # e.g., "enp0s3", "eth0" - LEAVE EMPTY TO AUTO-DETECT, OR SPECIFY

  

While WIFI_IFACE and ETHERNET_IFACE can often be auto-detected, explicitly setting them (e.g., WIFI_IFACE="wlp0s20f3") can prevent issues if you have multiple interfaces or if auto-detection fails.
For connect_to_hotspot.sh (on Client Linux machine):

Open the script in a text editor:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
nano connect_to_hotspot.sh

  

Adjust these lines:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
# --- !!! IMPORTANT: Customize these values !!! ---
WIFI_IFACE=""               # e.g., "wlp0s20f3", "wlan0" - LEAVE EMPTY TO AUTO-DETECT, OR SPECIFY
HOTSPOT_SSID="MyFedoraHotspot" # **MUST match the SSID set in setup_fedora_hotspot.sh**
HOTSPOT_PASSWORD="YourVerySecurePassword" # **MUST match the password set in setup_fedora_hotspot.sh**
HOTSPOT_CONN_NAME="Client Hotspot Connection" # A name for NetworkManager to store this connection profile

  

Ensure HOTSPOT_SSID and HOTSPOT_PASSWORD are identical to what you set in setup_fedora_hotspot.sh.
Step 3: Run the Fedora Hotspot Setup Script

On your Fedora machine, make the script executable and run it:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
chmod +x setup_fedora_hotspot.sh
sudo ./setup_fedora_hotspot.sh

  

The script will:

    Detect your interfaces (if not specified).

    Verify internet connectivity via Ethernet.

    Back up /etc/sysctl.conf and relevant NetworkManager/Firewalld configurations to a timestamped directory under /etc/fedora_hotspot_backup_YYYYMMDDHHMMSS.

    Install necessary packages.

    Configure NetworkManager for the hotspot.

    Enable IP forwarding.

    Ensure Firewalld is correctly configured for masquerading.

    Activate the hotspot.

    Display a summary of the setup and detailed troubleshooting information, logging everything to /var/log/fedora_hotspot_setup.log.

Important: Pay attention to any ERROR messages in the output. If the script reports a failure, consult the troubleshooting section.
Step 4: Run the Client Connection Script

On your Client Linux machine, make the script executable and run it:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
chmod +x connect_to_hotspot.sh
sudo ./connect_to_hotspot.sh

  

The script will:

    Detect your Wi-Fi interface (if not specified).

    Back up existing NetworkManager connection profiles to a timestamped directory under /etc/hotspot_client_backup_YYYYMMDDHHMMSS.

    Install necessary packages.

    Create and activate a NetworkManager connection profile to your Fedora hotspot.

    Attempt to verify internet connectivity.

    Display a summary of the connection and detailed troubleshooting information, logging everything to /var/log/hotspot_client_connect.log.

5. Troubleshooting

Both scripts are designed to provide extensive information for troubleshooting. If you encounter issues (e.g., hotspot not visible, clients connect but no internet), follow these steps.
General Troubleshooting Steps

    Review the Script Output: The terminal output (and the log files) will contain INFO, WARN, and ERROR messages. Read them carefully for clues.

    Check Log Files: For the Fedora machine, check /var/log/fedora_hotspot_setup.log. For the client, check /var/log/hotspot_client_connect.log. These logs contain all commands run and their full output.

    Use the troubleshoot option:

Using the troubleshoot option

If the main script execution fails or clients cannot connect, you can run the scripts in troubleshooting mode to gather current system state information without making changes.
On Fedora Hotspot machine:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
sudo ./setup_fedora_hotspot.sh troubleshoot

  

This will output comprehensive network diagnostics (NetworkManager status, IP configuration, Firewalld rules, sysctl settings, journal logs, dmesg). Copy this entire output for sharing or further analysis.
On Client Linux machine:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
sudo ./connect_to_hotspot.sh troubleshoot

  

This will provide client-side network diagnostics (NetworkManager status, IP configuration, DNS settings, ping tests, journal logs, dmesg). Copy this entire output for sharing or further analysis.
Using the recover option

If the scripts introduce unintended issues, you can use the recover option to get instructions on how to revert changes. Note that full automatic rollback is complex due to various system states; this option provides guidance and paths to your backups.
On Fedora Hotspot machine:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
sudo ./setup_fedora_hotspot.sh recover

  

This will print instructions on how to manually restore files from the backup directory (/etc/fedora_hotspot_backup_YYYYMMDDHHMMSS) and how to remove the created NetworkManager connection.
On Client Linux machine:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
sudo ./connect_to_hotspot.sh recover

  

This will print instructions on how to manually restore NetworkManager connection profiles from its backup directory (/etc/hotspot_client_backup_YYYYMMDDHHMMSS) and how to remove the created hotspot connection.
Using the reset option

This option specifically removes the NetworkManager connection profile created by the script. It does not revert sysctl or firewalld changes.
On Fedora Hotspot machine:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
sudo ./setup_fedora_hotspot.sh reset

  

This will delete the NetworkManager hotspot connection. You may need to manually restart NetworkManager (sudo systemctl restart NetworkManager) and revert other settings if necessary using the recover instructions.
On Client Linux machine:
code Bash
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END

    
sudo ./connect_to_hotspot.sh reset

  

This will delete the NetworkManager client connection to the hotspot.
6. License

This project is licensed under the MIT License - see the LICENSE file for details (you'll need to create this file if you haven't already, or choose a different license).
