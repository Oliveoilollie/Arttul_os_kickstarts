#!/bin/bash

# ==============================================================================
#  ArttulOS Automated ISO Builder v18.0 (The Simple, Absolute Path Fix)
#
#  - This script is a complete rewrite of the logic to be simple and robust.
#  - It determines the absolute path of all working directories and files
#    at the start.
#  - It uses these absolute paths for EVERY command, eliminating all errors
#    caused by changing directories.
#  - This is the definitive, correct, and most reliable implementation.
#
#  Written by: Natalie Spiva, ArttulOS Project
#  Rewritten and Corrected by: AI Assistant
# ==============================================================================

# --- Shell Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# --- Helper Functions ---
error_exit() {
    # This function now expects the absolute path to the build directory
    local build_dir_to_clean="$1"
    local error_message="$2"
    echo -e "\n${RED}BUILD FAILED: ${error_message}${NC}" >&2
    [ -n "$build_dir_to_clean" ] && [ -d "$build_dir_to_clean" ] && rm -rf "$build_dir_to_clean"
    exit 1
}

print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "\n${YELLOW}--> Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1${NC}"
}

# --- Configuration ---
DISTRO_NAME="ArttulOS"
ISO_URL="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.6-x86_64-dvd.iso"
ISO_FILENAME=$(basename "$ISO_URL")
DISTRO_VERSION="9.6"
ASSET_REPO_URL="https://github.com/Sprunglesonthehub/arttulos-assets.git"
SOURCE_SIDEBAR_IMAGE="A.png"
SOURCE_TOPBAR_IMAGE="fox.png"
KS_FILENAME="arttulos.ks"

# --- Script Internals ---
BUILD_DIR_NAME="build_temp"
ASSET_DIR_NAME="arttulos-assets"
BUILD_MODE="Interactive"; TOTAL_STEPS=8

# ============================ MAIN SCRIPT LOGIC ============================

generate_kickstart() {
    local kickstart_file_path="$1" # Expects absolute path to the kickstart file
    print_step "Generating Kickstart file for '${BUILD_MODE}' mode..."
    KS_LANG="en_US.UTF-8"; KS_TIMEZONE="America/New_York"; KS_HOSTNAME="arttulos-desktop"
    cat > "${kickstart_file_path}" <<EOF
graphical
lang ${KS_LANG}
keyboard --vckeymap=us --xlayouts='us'
timezone ${KS_TIMEZONE} --isUtc
cdrom
network --bootproto=dhcp --device=link --activate --hostname=${KS_HOSTNAME}
firewall --enabled --service=ssh
repo --name="elrepo-kernel" --baseurl=https://elrepo.org/linux/kernel/el9/x86_64/ --gpgkey=https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
zerombr
clearpart --all --initlabel
autopart --type=lvm
bootloader --location=mbr --boot-drive=sda
rootpw --lock
selinux --enforcing
%packages --excludedocs --instLangs=en_US
@workstation-product-environment
@guest-desktop-agents
gnome-initial-setup
kernel-ml
%end
EOF
    if [ "$BUILD_MODE" == "Appliance" ] || [ "$BUILD_MODE" == "OEM" ]; then
        echo "eula --agreed" >> "${kickstart_file_path}"; echo "reboot" >> "${kickstart_file_path}"
    fi
    if [ "$BUILD_MODE" == "Appliance" ]; then
        echo "user --name=arttulos --groups=wheel --password=arttulos --plaintext" >> "${kickstart_file_path}"
    fi
    cat >> "${kickstart_file_path}" <<'EOF'
%post --log=/root/ks-post.log --erroronfail
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
sed -i 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
rpm --import https://www.elrepo.org/RPM-GPG-KEY-v2-elrepo.org
ML_KERNEL_PATH=$(ls /boot/vmlinuz-*.elrepo.x86_64 | head -n 1)
if [ -z "$ML_KERNEL_PATH" ]; then exit 1; fi
grubby --set-default "${ML_KERNEL_PATH}"
GRUB_CFG_PATH=""
if [ -f /boot/grub2/grub.cfg ]; then GRUB_CFG_PATH="/boot/grub2/grub.cfg"; fi
if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then GRUB_CFG_PATH="/boot/efi/EFI/rocky/grub.cfg"; fi
if [ -z "$GRUB_CFG_PATH" ]; then exit 1; fi
grub2-mkconfig -o "${GRUB_CFG_PATH}"
sed -i "s#\(^\s*\)\(linux\|initrd\) /boot/#\2 /#" "${GRUB_CFG_PATH}"
EOF
    if [ "$BUILD_MODE" == "Appliance" ]; then
        cat >> "${kickstart_file_path}" <<EOF
chage -d 0 arttulos
echo "Welcome to ArttulOS Appliance. Default user/pass: arttulos/arttulos. You must change the password on first login." > /etc/motd
EOF
    else
        echo "Welcome to your new ArttulOS system." > /etc/motd
    fi
    echo "%end" >> "${kickstart_file_path}"
    echo -e "${GREEN}    Kickstart file generated successfully.${NC}"
}

main() {
    CURRENT_STEP=0
    if [[ "$1" == "--appliance" ]]; then BUILD_MODE="Appliance"; elif [[ "$1" == "--oem" ]]; then BUILD_MODE="OEM"; fi
    
    # --- Define ALL paths as absolute paths from the start ---
    local CWD; CWD="$(pwd)"
    local BUILD_DIR="${CWD}/${BUILD_DIR_NAME}"
    local BASE_ISO_PATH="${CWD}/${ISO_FILENAME}"
    local FINAL_ISO_NAME="${DISTRO_NAME}-${DISTRO_VERSION}-${BUILD_MODE}-Kernel-ML-Installer.iso"
    local FINAL_ISO_PATH="${CWD}/${FINAL_ISO_NAME}"
    local ASSET_DIR="${BUILD_DIR}/${ASSET_DIR_NAME}"
    local ISO_ROOT_DIR="${BUILD_DIR}/iso_root"
    local SQUASHFS_ROOT_DIR="${BUILD_DIR}/squashfs-root"
    local KICKSTART_PATH="${BUILD_DIR}/${KS_FILENAME}"

    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}  ArttulOS Automated ISO Builder v18.0                                ${NC}"
    echo -e "${BLUE}  Building in: ${YELLOW}${BUILD_MODE} Mode${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    
    echo -e "\n${BLUE}Starting the full ArttulOS build process...${NC}"
    rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR" || error_exit "$BUILD_DIR" "Could not create build directory: ${BUILD_DIR}"
    
    print_step "Checking for base ISO..."
    if [ ! -f "$BASE_ISO_PATH" ]; then
        read -p "    Base ISO '${ISO_FILENAME}' not found at '${CWD}'. Download now? [y/N]: " -n 1 -r REPLY; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then wget -O "$BASE_ISO_PATH" -c "$ISO_URL" || error_exit "$BUILD_DIR" "Download failed."; else error_exit "$BUILD_DIR" "User aborted."; fi
    else
        echo -e "${GREEN}    Found local base ISO.${NC}"
    fi

    print_step "Cloning branding assets..."
    git clone --quiet "$ASSET_REPO_URL" "$ASSET_DIR" || error_exit "$BUILD_DIR" "Failed to clone Git repo."
    echo -e "${GREEN}    Assets cloned.${NC}"

    print_step "Processing and resizing branding images..."
    convert "${ASSET_DIR}/${SOURCE_SIDEBAR_IMAGE}" -resize 180x230\! "${BUILD_DIR}/arttulos-sidebar.png" || error_exit "$BUILD_DIR" "ImageMagick failed to process sidebar image."
    convert "${ASSET_DIR}/${SOURCE_TOPBAR_IMAGE}" -resize 150x25\! "${BUILD_DIR}/arttulos-topbar.png" || error_exit "$BUILD_DIR" "ImageMagick failed to process topbar image."
    echo -e "${GREEN}    Images resized successfully.${NC}"
    
    generate_kickstart "$KICKSTART_PATH"

    print_step "Extracting base ISO contents..."
    7z x "$BASE_ISO_PATH" -o"$ISO_ROOT_DIR" > /dev/null || error_exit "$BUILD_DIR" "Failed to extract base ISO."
    echo -e "${GREEN}    ISO extracted.${NC}"

    print_step "Applying visual branding (unpacking installer...)"
    # Use -d with absolute paths. This is the correct, robust way.
    unsquashfs -d "$SQUASHFS_ROOT_DIR" "${ISO_ROOT_DIR}/images/install.img" || error_exit "$BUILD_DIR" "Failed to unpack install.img."
    
    cp -f "${BUILD_DIR}/arttulos-sidebar.png" "${SQUASHFS_ROOT_DIR}/usr/share/anaconda/pixmaps/sidebar-logo.png"
    cp -f "${BUILD_DIR}/arttulos-topbar.png"  "${SQUASHFS_ROOT_DIR}/usr/share/anaconda/pixmaps/topbar-logo.png"
    sed -i "s/NAME=\"Rocky Linux\"/NAME=\"${DISTRO_NAME}\"/" "${SQUASHFS_ROOT_DIR}/etc/os-release"
    sed -i "s/Rocky Linux release/${DISTRO_NAME} release/" "${SQUASHFS_ROOT_DIR}/etc/redhat-release"
    echo -e "${GREEN}    Visual branding applied.${NC}"

    print_step "Integrating Kickstart and repacking installer..."
    cp "$KICKSTART_PATH" "$ISO_ROOT_DIR/"
    rm "${ISO_ROOT_DIR}/images/install.img"
    mksquashfs "$SQUASHFS_ROOT_DIR" "${ISO_ROOT_DIR}/images/install.img" -noappend || error_exit "$BUILD_DIR" "Failed to repack install.img."
    
    local ISO_LABEL; ISO_LABEL=$(xorriso -indev "$BASE_ISO_PATH" -volid_get 2>/dev/null)
    if [ -z "$ISO_LABEL" ]; then error_exit "$BUILD_DIR" "Could not get Volume ID from base ISO. Path: ${BASE_ISO_PATH}"; fi
    
    local KS_PARAM="inst.ks=hd:LABEL=${ISO_LABEL}:/${KS_FILENAME}"
    sed -i "s/Rocky Linux/${DISTRO_NAME}/g" "${ISO_ROOT_DIR}/EFI/BOOT/grub.cfg"
    sed -i "s/Rocky Linux/${DISTRO_NAME}/g" "${ISO_ROOT_DIR}/isolinux/isolinux.cfg"
    sed -i "/^  linux/ s@\$@ ${KS_PARAM}@" "${ISO_ROOT_DIR}/EFI/BOOT/grub.cfg"
    sed -i "/^  append/ s@\$@ ${KS_PARAM}@" "${ISO_ROOT_DIR}/isolinux/isolinux.cfg"
    echo -e "${GREEN}    Bootloader configured for unattended install.${NC}"
    
    print_step "Rebuilding final ISO image..."
    # Use a subshell for the final cd to be perfectly clean and safe.
    (
        cd "$ISO_ROOT_DIR" || exit 1
        xorriso -as mkisofs -V "$ISO_LABEL" -o "$FINAL_ISO_PATH" -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efiboot.img -no-emul-boot -isohybrid-gpt-basdat . > /dev/null 2>&1
    ) || error_exit "$BUILD_DIR" "Failed to rebuild final ISO with xorriso."

    rm -rf "$BUILD_DIR"
    
    echo -e "\n${GREEN}======================================================================${NC}"
    echo -e "${GREEN}  BUILD COMPLETE!                                                     ${NC}"
    echo -e "${GREEN}  Your '${BUILD_MODE}' ArttulOS installer is ready:                   ${NC}"
    echo -e "${YELLOW}  ${FINAL_ISO_PATH}${NC}"
    echo -e "${GREEN}======================================================================${NC}"
}

main "$@"
