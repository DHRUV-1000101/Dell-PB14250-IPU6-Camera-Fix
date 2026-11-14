#!/bin/bash
set -e

# 1. Enforce sudo / root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo (e.g., sudo $0)"
    exit 1
fi

# 2. Get the directory where this script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# 3. Check running kernel vs. available kernel-devel (only if headers aren't already installed)
CURRENT_KERNEL=$(uname -r)

if [ ! -d "/lib/modules/$CURRENT_KERNEL/build" ]; then
    AVAILABLE_DEVEL=$(dnf repoquery --latest-limit=1 --qf "%{version}-%{release}.%{arch}" kernel-devel 2>/dev/null | head -n 1 || true)

    echo "Running kernel:          $CURRENT_KERNEL"
    echo "Available kernel-devel:  ${AVAILABLE_DEVEL:-Unknown}"

    if [ "$CURRENT_KERNEL" != "$AVAILABLE_DEVEL" ]; then
        echo ""
        echo "Kernel Mismatch Detected!"
        echo "Your running kernel ($CURRENT_KERNEL) does not match the available kernel-devel ($AVAILABLE_DEVEL)."
        echo ""
        echo "Please choose one of the following options before running this script again:"
        echo "  1. Upgrade your system & reboot (Recommended):"
        echo "       sudo dnf upgrade -y && sudo reboot"
        echo "  2. Manually install headers for your current kernel:"
        echo "       sudo dnf install -y kernel-devel-$CURRENT_KERNEL"
        echo ""
        exit 1
    fi
else
    echo "Running kernel:          $CURRENT_KERNEL (Headers already present)"
fi
echo "Kernel matched ($CURRENT_KERNEL). Continuing..."

# 4. Blacklist spd5118 module
echo "Blacklisting spd5118 in /etc/modprobe.d/blacklist-spd5118.conf..."
echo "blacklist spd5118" > /etc/modprobe.d/blacklist-spd5118.conf

# 5. Install dependencies
dnf install dkms kernel-devel-matched gcc make

# 6. Copy, build, and install each module with DKMS
MODULES=("hm1092-0.1" "ov05c10-0.1")

for mod in "${MODULES[@]}"; do
    # Split "hm1092-0.1" into NAME="hm1092" and VERSION="0.1"
    NAME="${mod%-*}"
    VERSION="${mod##*-}"

    if [ ! -d "$SCRIPT_DIR/$mod" ]; then
        echo "Error: Folder $SCRIPT_DIR/$mod not found."
        exit 1
    fi

    echo "----------------------------------------"
    echo "Processing $NAME ($VERSION)..."

    # Remove old DKMS registration if re-running the script
    if dkms status "$NAME/$VERSION" 2>/dev/null | grep -q "$NAME"; then
        dkms remove "$NAME/$VERSION" --all
    fi

    # Copy fresh source into /usr/src/
    rm -rf "/usr/src/${mod:?}"
    cp -r "$SCRIPT_DIR/$mod" /usr/src/

    # Register, build, and install
    dkms add "$NAME/$VERSION"
    dkms build "$NAME/$VERSION"
    dkms install "$NAME/$VERSION"

    echo "$NAME ($VERSION) installed successfully!"
done

echo "----------------------------------------"
echo "All modules built and installed. Current DKMS status:"
dkms status

# 7. Secure Boot / MOK enrollment notice
echo ""
echo "========================================================================"
echo "IMPORTANT: Secure Boot Notice"
echo "If Secure Boot is enabled on your system, unsigned/custom DKMS modules"
echo "will not load until you enroll the DKMS MOK."
echo ""
echo "Option 1: Enroll the DKMS key using command below"
echo "        sudo mokutil --import /var/lib/dkms/mok.pub"
echo "  Then reboot and follow the on-screen prompts"
echo ""
echo "Option 2: Disable Secure Boot"
echo "========================================================================"
