# Dell-PB14250-IPU6-Camera-Fix

This repository provides a working camera fix for the **Dell Pro 14 Plus (PB14250)** equipped with an **OmniVision OV05C10** RGB sensor and **Himax HM1092** IR sensor paired with a **Synaptics SVP7500** USBIO bridge on Intel **IPU6**.

It builds on top of the driver fixes proposed in [intel/ipu6-drivers#466](https://github.com/intel/ipu6-drivers/pull/466), adding an `hm1092` V4L2 subdev stub, `spd5118` I2C bus blacklisting, DKMS automation scripts, and a `libcamera` Software ISP color profile.

> **Note:** This fix is specifically intended for the **Dell Pro 14 Plus (PB14250)** running **Fedora** with Intel **IPU6**. Other laptops do not need this workaround.

---

## Installation

### Prerequisites

#### 1. Verify Software Stack (`libcamera` Only — No Proprietary Intel IPU6 Stack)

This fix relies on Fedora's built-in open-source **`libcamera` + Software ISP** stack and will **conflict with Intel's proprietary IPU6 stack**.

* Make sure you **do not** have the RPM Fusion proprietary IPU6 packages installed (`akmod-intel-ipu6`, `ipu6-camera-hal`, `gstreamer1-plugins-icamerasrc`, or `v4l2-relayd`). If you previously installed them, remove them first.

* Ensure `libcamera` and PipeWire `libcamera` support are installed (included by default on Fedora Workstation).

#### 2. Verify Hardware Match

Confirm that your laptop has the exact same camera hardware stack (**Intel IPU6**, **Synaptics SVP7500 bridge**, **OVTI05C1**, and **HIMX1092**) by running these commands in your terminal and comparing the output:

```bash
# 1. Check for Intel IPU6
lspci -nn | grep -i "8086:7d19"

# 2. Check for Synaptics SVP7500 USBIO Bridge
lsusb | grep -i "06cb:0701"

# 3. Check ACPI device IDs for OV05C10 (OVTI05C1) and Himax HM1092 (HIMX1092)
ls /sys/bus/acpi/devices/ | grep -E "OVTI05C1|HIMX1092"
```

Expected output:

* `lspci` shows `8086:7d19` (Intel IPU6 Imaging Unit).
* `lsusb` shows `06cb:0701 Synaptics, Inc.`.
* `/sys/bus/acpi/devices/` lists both `OVTI05C1:00` and `HIMX1092:00`.

*(Also ensure your system is booted into the latest installed kernel so your running kernel matches the available `kernel-devel` headers.)*

---

### Automatic Installation

#### 1. Clone the repository

```bash
git clone https://github.com/DHRUV-1000101/Dell-PB14250-IPU6-Camera-Fix.git
cd Dell-PB14250-IPU6-Camera-Fix
```

#### 2. Run the DKMS installer script

`install.sh` blacklists `spd5118`, installs `dkms` build dependencies, and builds/installs both `hm1092-0.1` and `ov05c10-0.1`:

```bash
sudo ./install.sh
```

> **Note:** If `install.sh` reports a kernel version mismatch, upgrade your system and reboot (`sudo dnf upgrade -y && sudo reboot`), then run `sudo ./install.sh` again.

#### 3. Enroll Secure Boot MOK Key & Reboot

If **Secure Boot** is enabled in your BIOS, enroll the DKMS Machine Owner Key so the kernel allows loading the custom modules, or disable Secure Boot in BIOS to test first:

```bash
# Check first how to enroll keys to get yourself familiar
sudo mokutil --import /var/lib/dkms/mok.pub
```

#### 4. Apply the Camera Color Profile (Optional)

After rebooting, assuming your camera is working, you can choose to go with the default calibration or create your own. `apply-color-profile.sh` installs a starter profile that you can customize to your liking.

*(After running the script, you can edit `/usr/share/libcamera/ipa/simple/ov05c10.yaml`, then restart `pipewire` and `wireplumber`.)*

```bash
./apply-color-profile.sh
```

---

### Manual Installation

If you prefer not to use the scripts, run each step manually:

```bash
# 1. Blacklist spd5118 to prevent I2C bus conflicts on the USBIO bridge
echo "blacklist spd5118" | sudo tee /etc/modprobe.d/blacklist-spd5118.conf

# 2. Install DKMS and kernel build tools
sudo dnf install -y dkms kernel-devel-matched gcc make

# 3. Copy driver sources to /usr/src/
sudo cp -r hm1092-0.1 ov05c10-0.1 /usr/src/

# 4. Register, build, and install both modules via DKMS
sudo dkms add hm1092/0.1
sudo dkms build hm1092/0.1
sudo dkms install hm1092/0.1

sudo dkms add ov05c10/0.1
sudo dkms build ov05c10/0.1
sudo dkms install ov05c10/0.1

# 5. Enroll Secure Boot key (if Secure Boot is enabled) and reboot
sudo mokutil --import /var/lib/dkms/mok.pub
sudo reboot

# 6. (Optional, after reboot) Install libcamera color profile and restart PipeWire
sudo install -m 644 ov05c10.yaml /usr/share/libcamera/ipa/simple/ov05c10.yaml
systemctl --user restart pipewire wireplumber
```

---

### Uninstallation

To cleanly remove both DKMS modules, delete `/usr/src/` sources, remove the `spd5118` blacklist, and delete the `ov05c10.yaml` profile:

```bash
sudo ./uninstall.sh
sudo reboot
```

---

## Root Cause

Getting the webcam working on the **Dell Pro 14 Plus (PB14250)** requires resolving four separate issues across the sensor driver, ACPI media graph, USBIO I2C bus, and `libcamera` ISP:

1. **Single Link-Frequency Firmware Mismatch (`ov05c10`):**
   The upstream `ov05c10` driver required *all* link frequencies in `ov05c10_link_freq_menu_items[]` (both 480 MHz and 900 MHz) to be present in firmware. However, the kernel's `ipu-bridge` only advertises a single frequency (`480000000`) for `OVTI05C1`, causing `ov05c10_parse_fwnode()` to fail probe with `-EINVAL` (fixed in [PR #466](https://github.com/intel/ipu6-drivers/pull/466) using `v4l2_link_freq_to_bitmap()`).
2. **Runtime PM Reference Underflow (`ov05c10`):**
   In `ov05c10_set_ctrl()`, the `V4L2_CID_VBLANK` handler attempted an I2C register read (`REG_TIMING_VTS`) before acquiring a runtime PM reference, timing out on a suspended sensor and triggering an unconditional `pm_runtime_put()` underflow (fixed in [PR #466](https://github.com/intel/ipu6-drivers/pull/466) by computing `height + vblank` directly).
3. **Blocked IPU6 Async Media Graph (`HIMX1092`):**
   The Synaptics SVP7500 bridge exposes both `OVTI05C1` (RGB) and `HIMX1092` (IR) sensors in ACPI. Intel's IPU6 async media graph waits for *every* declared sensor subdev to bind before registering the video capture pipeline. Without a driver bound to `HIMX1092`, the graph remains incomplete and `/dev/video*` never streams. The `hm1092` stub driver registers a minimal `MEDIA_ENT_F_CAM_SENSOR` subdev to unblock the pipeline.
4. **`spd5118` I2C Probing Conflict on `i2c-usbio` & Missing Software ISP Tuning:**
   The `spd5118` memory temperature sensor driver probes addresses on the Synaptics USBIO virtual I2C bus and interferes with camera sensor communication, requiring `spd5118` to be blacklisted.


## Upstream Kernel Status (Skipping `ov05c10` DKMS in the Future)

Once [intel/ipu6-drivers#466](https://github.com) is merged and updated into the upstream Linux kernel shipped by Fedora, the out-of-tree `ov05c10-0.1` DKMS module in this repository will no longer be necessary.

When running a kernel that already includes those upstream `ov05c10` fixes:

1. **Remove the `ov05c10` DKMS module** (if previously installed) so it does not override the in-tree kernel driver.

2. **Keep only the remaining workarounds** until they are also resolved upstream:
   * **`hm1092-0.1` stub** (required while `HIMX1092` is declared in ACPI without an upstream driver)
   * **`/etc/modprobe.d/blacklist-spd5118.conf`** (required until the `i2c-usbio` / `spd5118` probing conflict is resolved upstream)
   * **`ov05c10.yaml`** (required until `libcamera` ships a default tuning profile for `ov05c10`)
