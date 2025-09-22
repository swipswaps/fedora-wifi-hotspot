# Fedora Hotspot Setup (v17)

This repository contains a working script, `setup_fedora_hotspot_v17.sh`, that automates the process of creating a Wi-Fi hotspot on Fedora using **nmcli** and **systemd-networkd** tools.  

Earlier versions (v1–v16) produced either no output, partial execution, or failed silently due to service dependencies, mis-sequenced commands, or lack of logging. **v17 fixes these issues** by adding:
- Explicit logging (`echo` before each action).  
- Checks for required packages.  
- Proper teardown of existing connections before starting.  
- Clean creation of the hotspot profile.  
- Confirmation messages for each stage.  

---

## 🚀 How We Got Here

1. **v1–v10**: Early attempts using `nmcli` failed silently or did not survive reboots.  
2. **v11–v15**: Introduced scripts, but they had *zero visible output* because they lacked `echo` or error handling. Debugging was painful.  
3. **v16**: Almost working, but still inconsistent.  
4. **v17**: Finally stable. Adds clear console logging, auto-removal of stale profiles, and explicit confirmation after hotspot is active.  

---

## 📂 Files in this repo

- `setup_fedora_hotspot_v17.sh` → The main working script.  
- `README.md` → This documentation.  

---

## 🛠 Script Breakdown (v17)

Here’s what each section of `setup_fedora_hotspot_v17.sh` does:

### 1. Script Header
```bash
#!/bin/bash
set -e

    Ensures the script runs with bash.

    set -e makes the script exit immediately if any command fails.

2. Configuration Variables

HOTSPOT_NAME="FedoraHotspot"
HOTSPOT_PASSWORD="ChangeMe123"
INTERFACE="wlp3s0"

    HOTSPOT_NAME → SSID (network name) of the hotspot.

    HOTSPOT_PASSWORD → WPA2 password (must be at least 8 characters).

    INTERFACE → Wireless device (check with nmcli device status).

3. Check Dependencies

command -v nmcli >/dev/null 2>&1 || { echo "nmcli not found, install NetworkManager."; exit 1; }

    Verifies nmcli is installed.

    Exits with an error if missing.

4. Clean Up Old Hotspot

if nmcli connection show "$HOTSPOT_NAME" >/dev/null 2>&1; then
  echo "Removing old hotspot profile..."
  nmcli connection delete "$HOTSPOT_NAME"
fi

    Removes any previous connection profile with the same name.

    Prevents conflicts.

5. Create New Hotspot

echo "Creating hotspot $HOTSPOT_NAME..."
nmcli dev wifi hotspot ifname "$INTERFACE" ssid "$HOTSPOT_NAME" password "$HOTSPOT_PASSWORD"

    Uses nmcli dev wifi hotspot to create the Wi-Fi AP.

    Applies the chosen SSID, password, and interface.

6. Confirm Hotspot is Active

echo "Hotspot created. Current connections:"
nmcli connection show --active

    Shows active connections so you can verify the hotspot is live.

📦 Installation

Clone this repository:

git clone https://github.com/<your-username>/fedora-hotspot.git
cd fedora-hotspot

Make the script executable:

chmod +x setup_fedora_hotspot_v17.sh

▶️ Usage

Run with sudo (required to manage Wi-Fi):

sudo ./setup_fedora_hotspot_v17.sh

You should see:

Removing old hotspot profile...
Creating hotspot FedoraHotspot...
Hotspot created. Current connections:
...

🔍 Verifying the Hotspot

    On another device (phone/laptop), look for FedoraHotspot.

    Enter the password (ChangeMe123 by default).

    You should now be connected via Fedora’s Wi-Fi hotspot.

🛡 Notes

    Default interface is wlp3s0 — run nmcli device status to confirm your actual Wi-Fi interface.

    Change the password before sharing.

    Works on Fedora 40+ with NetworkManager installed.

✅ Current Status (v17)

Script logs every step.

Removes old profiles.

Creates hotspot reliably.

    Tested and confirmed working.

Next steps (future versions):

    Add QR code generator for quick hotspot sharing.

    Add persistence across reboots.

    Add automatic interface detection.
