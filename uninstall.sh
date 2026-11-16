#!/bin/bash
set -e

# 1. Enforce sudo / root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo (e.g., sudo $0)"
    exit 1
fi

# 2. Remove DKMS modules and /usr/src/ source folders
MODULES=("hm1092-0.1" "ov05c10-0.1")

for mod in "${MODULES[@]}"; do
    NAME="${mod%-*}"
    VERSION="${mod##*-}"

    echo "----------------------------------------"
    echo "Removing $NAME ($VERSION)..."

    # Unregister and uninstall from DKMS if present
    if dkms status "$NAME/$VERSION" 2>/dev/null | grep -q "$NAME"; then
        dkms remove "$NAME/$VERSION" --all
        echo "Removed $NAME/$VERSION from DKMS"
    else
        echo "$NAME/$VERSION was not registered in DKMS"
    fi

    # Delete source directory from /usr/src/
    if [ -d "/usr/src/${mod:?}" ]; then
        rm -rf "/usr/src/${mod:?}"
        echo "Deleted /usr/src/$mod"
    else
        echo "/usr/src/$mod not found"
    fi
done

# 3. Remove spd5118 blacklist file
BLACKLIST_FILE="/etc/modprobe.d/blacklist-spd5118.conf"
echo "----------------------------------------"
if [ -f "$BLACKLIST_FILE" ]; then
    rm -f "$BLACKLIST_FILE"
    echo "Deleted $BLACKLIST_FILE"
else
    echo "$BLACKLIST_FILE not found"
fi

# 4. Remove libcamera tuning file if installed
YAML_FILE="/usr/share/libcamera/ipa/simple/ov05c10.yaml"
if [ -f "$YAML_FILE" ]; then
    rm -f "$YAML_FILE"
    echo "Deleted $YAML_FILE"
fi

echo "----------------------------------------"
echo "Uninstallation complete! Please reboot your system to complete cleanup."
