#!/bin/bash

# ==============================================================================
# ArttulOS ISO Build Script (FINAL v2.8 - Fixes dracut/initramfs issue)
#
# Description:
# Creates a fully automated installer for a GNOME Desktop environment.
# This version adds a forced 'dracut' rebuild in the %post section to
# ensure the initramfs for the custom kernel is built correctly.
# ==============================================================================

set -e

# --- Configuration ---
PREP_KERNEL_DIR="local-rpms"
PREP_TOOLS_DIR="build-tools-rpms"
BUILD_DIR="arttulos-build"
ISO_EXTRACT_DIR="${BUILD_DIR}/iso_extracted"
CUSTOM_REPO_DIR="${ISO_EXTRACT_DIR}/custom_repo"
FINAL_ISO_NAME="ArttulOS-9-GNOME-Desktop-Installer.iso"
ISO_LABEL="ARTTULOS9"
FINAL_ISO_PATH="${PWD}/${FINAL_ISO_NAME}"

# --- Functions ---
print_msg() {
    local color=$1
    local message=$2
    case "$color" in
        "green") echo -e "\n\e[32m[SUCCESS]\e[0m ${message}" ;;
        "blue") echo -e "\n\e[34m[INFO]\e[0m ${message}" ;;
        "yellow") echo -e "\n\e[33m[WARN]\e[0m ${message}" ;;
        "red") echo -e "\n\e[31m[ERROR]\e[0m ${message}" >&2 ;;
    esac
}

# --- Main Script ---

# 1. Initial Checks and Setup
if [ "$EUID" -ne 0 ]; then
  print_msg "red" "This script must be run as root. Please use sudo."
  exit 1
fi

REQUIRED_CMDS=(xorriso createrepo_c)
if [ ! -f /usr/share/syslinux/isohdpfx.bin ]; then
    REQUIRED_CMDS+=(syslinux)
fi
MISSING_CMD=false
for cmd in "${REQUIRED_CMDS[@]}"; do
    if [ "$cmd" == "syslinux" ]; then
        [ ! -f /usr/share/syslinux/isohdpfx.bin ] && MISSING_CMD=true
    elif ! command -v "$cmd" &> /dev/null; then
        MISSING_CMD=true
    fi
    [ "$MISSING_CMD" = true ] && break
done

if [ "$MISSING_CMD" = true ]; then
    print_msg "yellow" "Build tools are missing. Installing from local cache..."
    if [ ! -d "${PREP_TOOLS_DIR}" ] || [ -z "$(ls -A "${PREP_TOOLS_DIR}"/*.rpm 2>/dev/null)" ]; then
        print_msg "red" "The '${PREP_TOOLS_DIR}' directory is missing or empty."
        exit 1
    fi
    dnf install -y ./${PREP_TOOLS_DIR}/*.rpm
    print_msg "green" "Build tools installed."
fi

if [ ! -d "${PREP_KERNEL_DIR}" ] || [ -z "$(ls -A "${PREP_KERNEL_DIR}"/*.rpm 2>/dev/null)" ]; then
    print_msg "red" "The '${PREP_KERNEL_DIR}' directory is missing or empty."
    exit 1
fi

print_msg "blue" "Cleaning up previous build..."
umount "${BUILD_DIR}/iso_mount" &>/dev/null || true
rm -rf "${BUILD_DIR}"

print_msg "blue" "Creating build workspace..."
mkdir -p "${BUILD_DIR}/iso_mount" "${ISO_EXTRACT_DIR}" "${CUSTOM_REPO_DIR}"

# 2. Extract Base ISO
read -p "Please enter the full path to the official Rocky Linux 9 DVD ISO file: " BASE_ISO_PATH
if [ ! -f "$BASE_ISO_PATH" ]; then
    print_msg "red" "ISO file not found at '${BASE_ISO_PATH}'."
    exit 1
fi
print_msg "blue" "Mounting and extracting the base ISO..."
mount -o loop,ro "$BASE_ISO_PATH" "${BUILD_DIR}/iso_mount"
rsync -a -H --exclude=TRANS.TBL "${BUILD_DIR}/iso_mount/" "${ISO_EXTRACT_DIR}"
umount "${BUILD_DIR}/iso_mount"
chmod -R u+w "${ISO_EXTRACT_DIR}"

# 3. Create Custom Repository
print_msg "blue" "Copying kernel RPMs and creating simple custom repo..."
cp "${PREP_KERNEL_DIR}"/*.rpm "${CUSTOM_REPO_DIR}/"
createrepo_c "${CUSTOM_REPO_DIR}"

# 4. Create and Inject the GNOME Desktop Kickstart File
print_msg "blue" "Generating Kickstart file for GNOME Desktop installation..."
cat << EOF > "${ISO_EXTRACT_DIR}/ks.cfg"
# Kickstart file for ArttulOS (GNOME Desktop Edition)
graphical
repo --name="BaseOS" --baseurl=file:///run/install/repo/BaseOS
repo --name="AppStream" --baseurl=file:///run/install/repo/AppStream
repo --name="custom-kernel" --baseurl=file:///run/install/repo/custom_repo
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone America/Los_Angeles --isUtc
network --onboot=yes --device=eth0 --bootproto=dhcp --ipv6=auto --activate
network --hostname=arttulos.localdomain
firewall --enabled --service=ssh
selinux --enforcing
rootpw --plaintext arttulos
zerombr
clearpart --all --initlabel
autopart --type=lvm
bootloader --location=mbr
reboot

%packages --instLangs=en_US --excludedocs
@workstation-product-environment
kernel-ml
kernel-ml-devel
policycoreutils-python-utils
vim-enhanced
kexec-tools
%end

%post --log=/root/ks-post.log
echo "Starting ArttulOS post-installation script..."

useradd ArttulOS -c "ArttulOS Admin"
usermod -aG wheel ArttulOS
echo "ArttulOS:arttulos" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# --- FIX: Force a rebuild of the initramfs for the new kernel ---
# This ensures all necessary drivers (LVM, disk, etc.) are included,
# preventing the system from dropping to a dracut emergency shell on boot.
echo "Forcing rebuild of dracut initramfs to include all drivers..."
dracut --force --verbose

# Set the ELRepo kernel as default
grub2-set-default 0

# Create the first-boot service to install online apps
cat << 'SCRIPT_EOF' > /usr/local/sbin/arttulos-first-boot-setup.sh
#!/bin/bash
LOG_FILE="/var/log/arttulos-first-boot.log"
echo "--- ArttulOS First-Boot Setup Started at \$(date) ---" | tee -a \$LOG_FILE
sleep 15
echo "Installing Firefox, Gajim, and Element..." | tee -a \$LOG_FILE
dnf install -y firefox gajim element-desktop | tee -a \$LOG_FILE
echo "Application installation complete." | tee -a \$LOG_FILE
cat << 'MOTD_EOF' > /etc/motd

            (Genesis for the Ascii)

        Welcome to ArttulOS
      This system is running a mainline kernel from ELRepo.
      First boot setup is complete.

MOTD_EOF
echo "--- ArttulOS First-Boot Setup Finished at \$(date) ---" | tee -a \$LOG_FILE
SCRIPT_EOF
chmod +x /usr/local/sbin/arttulos-first-boot-setup.sh
cat << 'SERVICE_EOF' > /etc/systemd/system/arttulos-first-boot.service
[Unit]
Description=ArttulOS First-Boot Online Application Installer
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/arttulos-first-boot-setup.sh
ExecStartPost=/bin/rm -f /usr/local/sbin/arttulos-first-boot-setup.sh
ExecStartPost=/bin/systemctl disable arttulos-first-boot.service
[Install]
WantedBy=multi-user.target
SERVICE_EOF
systemctl enable arttulos-first-boot.service

echo "Post-installation script finished."
%end
EOF

# 5. Modify Bootloader to be Fully Automatic
print_msg "blue" "Modifying bootloader for fully automatic installation..."
ISOLINUX_CFG="${ISO_EXTRACT_DIR}/isolinux/isolinux.cfg"
GRUB_CFG="${ISO_EXTRACT_DIR}/EFI/BOOT/grub.cfg"
KS_APPEND="inst.stage2=hd:LABEL=${ISO_LABEL} quiet inst.ks=hd:LABEL=${ISO_LABEL}:/ks.cfg"

sed -i 's/timeout 600/timeout 10/' "$ISOLINUX_CFG"
sed -i "/menu label ^Install Rocky Linux 9/c\label arttulos\n  menu label ^Install ArttulOS\n  menu default\n  kernel vmlinuz\n  append initrd=initrd.img ${KS_APPEND}" "$ISOLINUX_CFG"
sed -i '/menu label ^Test this media/d' "$ISOLINUX_CFG"
sed -i '/menu label ^Troubleshooting/d' "$ISOLINUX_CFG"
sed -i "s|linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${ISO_LABEL} quiet|linuxefi /images/pxeboot/vmlinuz ${KS_APPEND}|" "$GRUB_CFG"

# 6. Rebuild the ISO with xorriso
print_msg "blue" "Building the final ISO using xorriso..."
cd "${ISO_EXTRACT_DIR}"
xorriso -as mkisofs \
  -V "${ISO_LABEL}" \
  -o "${FINAL_ISO_PATH}" \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e images/efiboot.img \
  -no-emul-boot \
  -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
  .
cd ..
chown "$(logname)":"$(logname)" "${FINAL_ISO_PATH}"

print_msg "green" "Build complete!"
echo -e "Your new ISO is located at: \e[1m${FINAL_ISO_PATH}\e[0m"
