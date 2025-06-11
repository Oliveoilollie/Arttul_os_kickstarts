#!/bin/bash

# ==============================================================================
# ArttulOS ISO Build Script (FINAL v3.2 - Corrected Credentials)
#
# Description:
# - Sets the username and password correctly to 'arttulos' for both.
# - Implements full ArttulOS branding: Plymouth boot splash, login screen,
#   and desktop wallpaper using the provided 'scripts/strix.png' file.
# ==============================================================================

set -e

# --- Configuration ---
PREP_KERNEL_DIR="local-rpms"
PREP_TOOLS_DIR="build-tools-rpms"
BUILD_DIR="arttulos-build"
ISO_EXTRACT_DIR="${BUILD_DIR}/iso_extracted"
CUSTOM_REPO_DIR="${ISO_EXTRACT_DIR}/custom_repo"
BRANDING_DIR="scripts"
WALLPAPER_FILE="strix.png"
FINAL_ISO_NAME="ArttulOS-9-GNOME-Branded-Installer.iso"
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

if [ ! -f "${BRANDING_DIR}/${WALLPAPER_FILE}" ]; then
    print_msg "red" "Branding file not found at '${BRANDING_DIR}/${WALLPAPER_FILE}'."
    exit 1
fi

REQUIRED_CMDS=(xorriso createrepo_c)
if [ ! -f /usr/share/syslinux/isohdpfx.bin ]; then REQUIRED_CMDS+=(syslinux); fi
MISSING_CMD=false
for cmd in "${REQUIRED_CMDS[@]}"; do
    if [ "$cmd" == "syslinux" ] && [ ! -f /usr/share/syslinux/isohdpfx.bin ]; then MISSING_CMD=true;
    elif ! command -v "$cmd" &> /dev/null; then MISSING_CMD=true; fi
    [ "$MISSING_CMD" = true ] && break
done

if [ "$MISSING_CMD" = true ]; then
    print_msg "yellow" "Build tools are missing. Installing from local cache..."
    if [ ! -d "${PREP_TOOLS_DIR}" ] || [ -z "$(ls -A "${PREP_TOOLS_DIR}"/*.rpm 2>/dev/null)" ]; then print_msg "red" "The '${PREP_TOOLS_DIR}' directory is missing or empty." && exit 1; fi
    dnf install -y ./${PREP_TOOLS_DIR}/*.rpm
    print_msg "green" "Build tools installed."
fi

if [ ! -d "${PREP_KERNEL_DIR}" ] || [ -z "$(ls -A "${PREP_KERNEL_DIR}"/*.rpm 2>/dev/null)" ]; then print_msg "red" "The '${PREP_KERNEL_DIR}' directory is missing or empty." && exit 1; fi

print_msg "blue" "Cleaning up previous build..."
umount "${BUILD_DIR}/iso_mount" &>/dev/null || true
rm -rf "${BUILD_DIR}"

print_msg "blue" "Creating build workspace..."
mkdir -p "${BUILD_DIR}/iso_mount" "${ISO_EXTRACT_DIR}" "${CUSTOM_REPO_DIR}"

# 2. Extract Base ISO and Inject Branding
read -p "Please enter the full path to the official Rocky Linux 9 DVD ISO file: " BASE_ISO_PATH
if [ ! -f "$BASE_ISO_PATH" ]; then print_msg "red" "ISO file not found at '${BASE_ISO_PATH}'." && exit 1; fi
print_msg "blue" "Mounting and extracting the base ISO..."
mount -o loop,ro "$BASE_ISO_PATH" "${BUILD_DIR}/iso_mount"
rsync -a -H --exclude=TRANS.TBL "${BUILD_DIR}/iso_mount/" "${ISO_EXTRACT_DIR}"
umount "${BUILD_DIR}/iso_mount"
chmod -R u+w "${ISO_EXTRACT_DIR}"

print_msg "blue" "Injecting branding assets into the ISO structure..."
mkdir -p "${ISO_EXTRACT_DIR}/branding"
cp "${BRANDING_DIR}/${WALLPAPER_FILE}" "${ISO_EXTRACT_DIR}/branding/"

# 3. Create Custom Repository
print_msg "blue" "Copying kernel RPMs and creating simple custom repo..."
cp "${PREP_KERNEL_DIR}"/*.rpm "${CUSTOM_REPO_DIR}/"
createrepo_c "${CUSTOM_REPO_DIR}"

# 4. Create and Inject the Branded Kickstart File
print_msg "blue" "Generating Kickstart file with full branding..."
cat << EOF > "${ISO_EXTRACT_DIR}/ks.cfg"
# Kickstart file for ArttulOS (GNOME Desktop Edition with Full Branding)
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
plymouth-scripts
%end

%post --log=/root/ks-post.log
echo "Starting ArttulOS post-installation script..."

# --- FIX: Create the 'arttulos' user with the correct password ---
echo "Creating user 'arttulos'..."
useradd arttulos -c "ArttulOS User"
usermod -aG wheel arttulos
echo "arttulos:arttulos" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# --- 1. COPY BRANDING ASSETS ---
echo "Copying branding assets..."
INSTALLER_BRANDING_DIR="/run/install/repo/branding"
SYSTEM_WALLPAPER_DIR="/usr/share/backgrounds/arttulos"
mkdir -p \$SYSTEM_WALLPAPER_DIR
cp "\${INSTALLER_BRANDING_DIR}/strix.png" "\${SYSTEM_WALLPAPER_DIR}/strix.png"

# --- 2. CREATE AND SET PLYMOUTH BOOT THEME ---
echo "Creating Plymouth boot splash theme..."
PLYMOUTH_THEME_DIR="/usr/share/plymouth/themes/arttulos"
mkdir -p \$PLYMOUTH_THEME_DIR
cp "\${SYSTEM_WALLPAPER_DIR}/strix.png" "\${PLYMOUTH_THEME_DIR}/"

cat << PLYMOUTH_EOF > \${PLYMOUTH_THEME_DIR}/arttulos.plymouth
[Plymouth Theme]
Name=ArttulOS
Description=ArttulOS Boot Splash
ModuleName=script

[script]
ImageDir=\${PLYMOUTH_THEME_DIR}
ScriptFile=\${PLYMOUTH_THEME_DIR}/arttulos.script
PLYMOUTH_EOF

cat << SCRIPT_EOF > \${PLYMOUTH_THEME_DIR}/arttulos.script
wallpaper_image = Image("strix.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
resized_wallpaper_image = wallpaper_image.Scale(screen_width, screen_height);
wallpaper_sprite = Sprite(resized_wallpaper_image);
wallpaper_sprite.SetZ(-100);
SCRIPT_EOF

echo "Setting new Plymouth theme and rebuilding initramfs..."
plymouth-set-default-theme arttulos -R

# --- 3. SET GNOME DESKTOP AND LOGIN WALLPAPER ---
echo "Configuring GDM login and user desktop backgrounds..."
GSETTINGS_OVERRIDES_DIR="/etc/dconf/db/local.d"
GDM_OVERRIDES_DIR="/etc/dconf/db/gdm.d"
WALLPAPER_PATH="/usr/share/backgrounds/arttulos/strix.png"

mkdir -p \$GSETTINGS_OVERRIDES_DIR
mkdir -p \$GDM_OVERRIDES_DIR

cat << GSETTINGS_EOF > \${GSETTINGS_OVERRIDES_DIR}/01-arttulos-branding
[org/gnome/desktop/background]
picture-uri='file://\${WALLPAPER_PATH}'
picture-uri-dark='file://\${WALLPAPER_PATH}'

[org/gnome/desktop/screensaver]
picture-uri='file://\${WALLPAPER_PATH}'
GSETTINGS_EOF

cat << GDM_EOF > \${GDM_OVERRIDES_DIR}/01-arttulos-branding
[org/gnome/desktop/background]
picture-uri='file://\${WALLPAPER_PATH}'
picture-uri-dark='file://\${WALLPAPER_PATH}'
GDM_EOF

dconf update

# Set the ELRepo kernel as default
grub2-set-default 0

# Create the first-boot service to install online apps
cat << 'SERVICE_SCRIPT_EOF' > /usr/local/sbin/arttulos-first-boot-setup.sh
#!/bin/bash
dnf install -y firefox gajim element-desktop
SERVICE_SCRIPT_EOF
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
print_msg "blue" "Overwriting bootloader configs for fully automatic installation..."
ISOLINUX_CFG="${ISO_EXTRACT_DIR}/isolinux/isolinux.cfg"
GRUB_CFG="${ISO_EXTRACT_DIR}/EFI/BOOT/grub.cfg"
KS_APPEND="inst.stage2=hd:LABEL=${ISO_LABEL} quiet inst.ks=hd:LABEL=${ISO_LABEL}:/ks.cfg"

cat << EOF > "${ISOLINUX_CFG}"
default vesamenu.c32
timeout 10
menu title ArttulOS 9 Installer
label install
  menu label ^Install ArttulOS
  menu default
  kernel vmlinuz
  append initrd=initrd.img ${KS_APPEND}
EOF

cat << EOF > "${GRUB_CFG}"
set timeout=1
menuentry 'Install ArttulOS' --class gnu-linux --class gnu --class os {
	linuxefi /images/pxeboot/vmlinuz ${KS_APPEND}
	initrdefi /images/pxeboot/initrd.img
}
EOF

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
