#!/bin/bash

# ==============================================================================
#  ArttulOS Automated ISO Builder v9.5 (Robust Unsquashfs Syntax)
#
#  - Corrects the unsquashfs command to use a more robust, default syntax
#    that is compatible across different tool versions. This resolves the
#    "help text" error.
#
#  Written by: Natalie Spiva, ArttulOS Project
# ==============================================================================

# --- Shell Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# --- Helper Functions ---
error_exit() {
    echo -e "\n${RED}BUILD FAILED: $1${NC}" >&2
    [ -d "$BUILD_DIR" ] && rm -rf "$BUILD_DIR"
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
BUILD_DIR="build_temp"; ASSET_DIR="arttulos-assets"
BUILD_MODE="Interactive"; TOTAL_STEPS=8

# ============================ MAIN SCRIPT LOGIC ============================

generate_kickstart() {
    print_step "Generating Kickstart file for '${BUILD_MODE}' mode..."
    KS_LANG="en_US.UTF-8"; KS_TIMEZONE="America/New_York"; KS_HOSTNAME="arttulos-desktop"
    cat > "$BUILD_DIR/$KS_FILENAME" <<EOF
graphical
lang ${KS_LANG}
keyboard --vckeymap=us --xlayouts='us'
timezone ${KS_TIMEZONE} --isUtc
cdrom
network --bootproto=dhcp --device=link --activate --hostname=${KS_HOSTNAME}
firewall --enabled --service=ssh
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
%end
EOF
    if [ "$BUILD_MODE" == "Appliance" ] || [ "$BUILD_MODE" == "OEM" ]; then
        echo "eula --agreed" >> "$BUILD_DIR/$KS_FILENAME"
        echo "reboot" >> "$BUILD_DIR/$KS_FILENAME"
    fi
    if [ "$BUILD_MODE" == "Appliance" ]; then
        echo "user --name=arttulos --groups=wheel --password=arttulos --plaintext" >> "$BUILD_DIR/$KS_FILENAME"
    fi
    cat >> "$BUILD_DIR/$KS_FILENAME" <<EOF
%post --log=/root/ks-post.log --erroronfail
echo "--- Starting ArttulOS Post-Installation Script (${BUILD_MODE} mode) ---"
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
sed -i 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
EOF
    if [ "$BUILD_MODE" == "Appliance" ]; then
        cat >> "$BUILD_DIR/$KS_FILENAME" <<EOF
chage -d 0 arttulos
echo "Welcome to ArttulOS Appliance. Default user/pass: arttulos/arttulos. You must change the password on first login." > /etc/motd
EOF
    elif [ "$BUILD_MODE" == "OEM" ]; then
        cat >> "$BUILD_DIR/$KS_FILENAME" <<'EOF'
cat << SERVICE_EOF > /etc/systemd/system/oem-setup.service
[Unit]
Description=ArttulOS First Boot Setup Wizard
After=graphical.target
[Service]
Type=oneshot
ExecStart=/usr/libexec/gnome-initial-setup --existing-user
ExecStartPost=/usr/bin/systemctl disable oem-setup.service
[Install]
WantedBy=graphical.target
SERVICE_EOF
systemctl enable oem-setup.service
EOF
    else
        echo "Welcome to your new ArttulOS system." > /etc/motd
    fi
    echo "--- Post-installation script finished successfully. ---" >> "$BUILD_DIR/$KS_FILENAME"
    echo "%end" >> "$BUILD_DIR/$KS_FILENAME"
    echo -e "${GREEN}    Kickstart file generated successfully.${NC}"
}

main() {
    # Initialize State
    CURRENT_STEP=0
    if [[ "$1" == "--appliance" ]]; then BUILD_MODE="Appliance"; elif [[ "$1" == "--oem" ]]; then BUILD_MODE="OEM"; fi
    FINAL_ISO_NAME="${DISTRO_NAME}-${DISTRO_VERSION}-${BUILD_MODE}-Installer.iso"

    # Banner
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}  ArttulOS Automated ISO Builder v9.5                                 ${NC}"
    echo -e "${BLUE}  Building in: ${YELLOW}${BUILD_MODE} Mode${NC} (Default is Interactive)"
    echo -e "${BLUE}======================================================================${NC}"

    # Build Process
    echo -e "\n${BLUE}Starting the full ArttulOS build process...${NC}"
    rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR" || error_exit "Could not create build directory."
    
    print_step "Checking for base ISO and downloading if needed..."
    if [ ! -f "$ISO_FILENAME" ]; then
        read -p "    Base ISO '${ISO_FILENAME}' not found. Download now? (~9GB) [y/N]: " -n 1 -r REPLY; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then wget -c "$ISO_URL" || error_exit "Download failed."; else error_exit "User aborted."; fi
    else
        echo -e "${GREEN}    Found local base ISO.${NC}"
    fi

    print_step "Cloning branding assets from GitHub..."
    git clone --quiet "$ASSET_REPO_URL" "$BUILD_DIR/$ASSET_DIR" || error_exit "Failed to clone Git repo."
    echo -e "${GREEN}    Assets cloned.${NC}"

    print_step "Processing and resizing branding images..."
    local sidebar_src_path="$BUILD_DIR/$ASSET_DIR/$SOURCE_SIDEBAR_IMAGE"
    local topbar_src_path="$BUILD_DIR/$ASSET_DIR/$SOURCE_TOPBAR_IMAGE"
    if [ ! -f "$sidebar_src_path" ]; then error_exit "Source sidebar image not found: $sidebar_src_path"; fi
    if [ ! -f "$topbar_src_path" ]; then error_exit "Source topbar image not found: $topbar_src_path"; fi
    convert "$sidebar_src_path" -resize 180x230\! "$BUILD_DIR/arttulos-sidebar.png" || error_exit "ImageMagick failed to process sidebar image."
    convert "$topbar_src_path" -resize 150x25\! "$BUILD_DIR/arttulos-topbar.png" || error_exit "ImageMagick failed to process topbar image."
    echo -e "${GREEN}    Images resized successfully.${NC}"
    
    generate_kickstart

    print_step "Extracting base ISO contents..."
    7z x "$ISO_FILENAME" -o"$BUILD_DIR/iso_root" > /dev/null || error_exit "Failed to extract base ISO."
    echo -e "${GREEN}    ISO extracted.${NC}"

    cd "$BUILD_DIR" || error_exit "Could not enter build directory."

    print_step "Applying visual branding (unpacking installer...)"
    # <<< FIX IS HERE >>> Using a simpler, more robust syntax for unsquashfs.
    # This command relies on the default behavior of creating 'squashfs-root' in the current directory.
    unsquashfs -progress "iso_root/images/install.img" || error_exit "Failed to unpack install.img."
    
    cp -f "arttulos-sidebar.png" "squashfs-root/usr/share/anaconda/pixmaps/sidebar-logo.png"
    cp -f "arttulos-topbar.png"  "squashfs-root/usr/share/anaconda/pixmaps/topbar-logo.png"
    sed -i "s/NAME=\"Rocky Linux\"/NAME=\"${DISTRO_NAME}\"/" "squashfs-root/etc/os-release"
    sed -i "s/Rocky Linux release/${DISTRO_NAME} release/" "squashfs-root/etc/redhat-release"
    echo -e "${GREEN}    Visual branding applied.${NC}"

    print_step "Integrating Kickstart and repacking installer..."
    cp "$KS_FILENAME" "iso_root/"
    rm "iso_root/images/install.img"
    mksquashfs "squashfs-root" "iso_root/images/install.img" -noappend -progress || error_exit "Failed to repack install.img."
    
    ISO_LABEL=$(isoinfo -d -i ../"$ISO_FILENAME" | grep "Volume id" | awk -F': ' '{print $2}')
    KS_PARAM="inst.ks=hd:LABEL=${ISO_LABEL}:/${KS_FILENAME}"
    
    sed -i "/^  linux/ s@\$@ ${KS_PARAM}@" "iso_root/EFI/BOOT/grub.cfg"
    sed -i "/^  append/ s@\$@ ${KS_PARAM}@" "iso_root/isolinux/isolinux.cfg"
    echo -e "${GREEN}    Bootloader configured for unattended install.${NC}"
    
    print_step "Rebuilding final ISO image..."
    cd "iso_root" || error_exit "Could not enter final build directory."
    xorriso -as mkisofs -V "${ISO_LABEL}" -o "../../${FINAL_ISO_NAME}" -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efiboot.img -no-emul-boot -isohybrid-gpt-basdat . > /dev/null 2>&1 || error_exit "Failed to rebuild final ISO."
    cd ../..
    rm -rf "$BUILD_DIR"
    
    # Success
    echo -e "\n${GREEN}======================================================================${NC}"
    echo -e "${GREEN}  BUILD COMPLETE!                                                     ${NC}"
    echo -e "${GREEN}  Your '${BUILD_MODE}' ArttulOS installer is ready:                   ${NC}"
    echo -e "${YELLOW}  $(pwd)/${FINAL_ISO_NAME}${NC}"
    echo -e "${GREEN}======================================================================${NC}"
}

main "$@"
