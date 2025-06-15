#!/bin/bash

# ==============================================================================
#  ArttulOS Automated ISO Builder v8.1 (RHEL 9.4+ Compatible)
#
#  Fixes the build process for modern Rocky/AlmaLinux 9.4+ ISOs by targeting
#  the new 'install.img' file instead of the legacy 'squashfs.img'.
#
#  Written by: Natalie Spiva, ArttulOS Project
# ==============================================================================

# --- Shell Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# --- Error Handling ---
error_exit() {
    echo -e "\n${RED}BUILD FAILED: $1${NC}" >&2
    [ -d "$BUILD_DIR" ] && rm -rf "$BUILD_DIR"
    exit 1
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
KS_LANG="en_US.UTF-8"
KS_TIMEZONE="America/New_York"
KS_HOSTNAME="arttulos-desktop"

# --- Script Internals ---
BUILD_DIR="build_temp"; ASSET_DIR="arttulos-assets"
FINAL_SIDEBAR_PNG="arttulos-sidebar.png"; FINAL_TOPBAR_PNG="arttulos-topbar.png"
BUILD_MODE="Interactive"

# ============================ MAIN SCRIPT LOGIC ============================

generate_kickstart() {
    echo -e "\n${YELLOW}--> Step 3: Generating Kickstart file for '${BUILD_MODE}' mode...${NC}"
    
    # Common Kickstart Settings
    cat << EOF > "$BUILD_DIR/$KS_FILENAME"
# Kickstart for ArttulOS - ${BUILD_MODE} Graphical Install
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

    # Mode-Specific Automation Settings
    if [ "$BUILD_MODE" == "Appliance" ] || [ "$BUILD_MODE" == "OEM" ]; then
        cat << EOF >> "$BUILD_DIR/$KS_FILENAME"
eula --agreed
reboot
EOF
    fi
    if [ "$BUILD_MODE" == "Appliance" ]; then
        cat << EOF >> "$BUILD_DIR/$KS_FILENAME"
user --name=arttulos --groups=wheel --password=arttulos --plaintext
EOF
    fi

    # Post-Install Script
    cat << EOF >> "$BUILD_DIR/$KS_FILENAME"
%post --log=/root/ks-post.log --erroronfail
echo "--- Starting ArttulOS Post-Installation Script (${BUILD_MODE} mode) ---"
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
sed -i 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
EOF

    if [ "$BUILD_MODE" == "Appliance" ]; then
        cat << EOF >> "$BUILD_DIR/$KS_FILENAME"
echo "Forcing password expiry for the default user..."
chage -d 0 arttulos
cat << MOTD_EOF > /etc/motd
Welcome to ArttulOS Appliance. Default user/pass: arttulos/arttulos. You must change the password on first login.
MOTD_EOF
EOF
    elif [ "$BUILD_MODE" == "OEM" ]; then
        cat << EOF >> "$BUILD_DIR/$KS_FILENAME"
echo "Creating and enabling the OEM first-boot setup service..."
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
    else # Interactive Mode
        cat << EOF >> "$BUILD_DIR/$KS_FILENAME"
cat << MOTD_EOF > /etc/motd
Welcome to your new ArttulOS system.
MOTD_EOF
EOF
    fi

    cat << EOF >> "$BUILD_DIR/$KS_FILENAME"
echo "--- Post-installation script finished successfully. ---"
%end
EOF
    echo -e "${GREEN}    Kickstart file generated successfully.${NC}"
}

main() {
    # Process Command-Line Arguments
    if [[ "$1" == "--appliance" ]]; then
        BUILD_MODE="Appliance"
    elif [[ "$1" == "--oem" ]]; then
        BUILD_MODE="OEM"
    fi
    FINAL_ISO_NAME="${DISTRO_NAME}-${DISTRO_VERSION}-${BUILD_MODE}-Installer.iso"

    # Banner
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}  ArttulOS Automated ISO Builder v8.1                                 ${NC}"
    echo -e "${BLUE}  Building in: ${YELLOW}${BUILD_MODE} Mode${NC} (Default is Interactive)"
    echo -e "${BLUE}======================================================================${NC}"

    # Pre-flight Checks
    if [ ! -f "$ISO_FILENAME" ]; then
        echo -e "\n${YELLOW}Base ISO '${ISO_FILENAME}' not found.${NC}"
        read -p "Do you want to download it now? (~9GB) [y/N]: " -n 1 -r REPLY; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            wget -c "$ISO_URL" || error_exit "Download failed."
        else
            error_exit "User aborted."
        fi
    fi

    # Build Process
    echo -e "\n${BLUE}Starting the full ArttulOS build process...${NC}"
    rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR" || error_exit "Could not create build directory."
    
    echo -e "\n${YELLOW}--> Steps 1 & 2: Fetching and processing assets...${NC}"
    git clone --quiet "$ASSET_REPO_URL" "$BUILD_DIR/$ASSET_DIR" || error_exit "Failed to clone Git repo."
    convert "$BUILD_DIR/$ASSET_DIR/$SOURCE_SIDEBAR_IMAGE" -resize 180x230\! "$BUILD_DIR/$FINAL_SIDEBAR_PNG" || error_exit "Failed to process sidebar image."
    convert "$BUILD_DIR/$ASSET_DIR/$SOURCE_TOPBAR_IMAGE" -resize 150x25\! "$BUILD_DIR/$FINAL_TOPBAR_PNG" || error_exit "Failed to process topbar image."
    echo -e "${GREEN}    Assets ready.${NC}"
    
    generate_kickstart

    echo -e "\n${YELLOW}--> Steps 4 & 5: Unpacking ISO and applying visual branding...${NC}"
    7z x "$ISO_FILENAME" -o"$BUILD_DIR/iso_root" > /dev/null || error_exit "Failed to extract base ISO."
    cd "$BUILD_DIR" || error_exit "Could not enter build directory."
    
    # <<< FIX IS HERE >>>
    # Unpack the NEW 'install.img' file instead of the old 'squashfs.img'
    unsquashfs iso_root/images/install.img > /dev/null || error_exit "Failed to unpack install.img. The base ISO may be corrupt or an unsupported version."
    
    cp -f "$FINAL_SIDEBAR_PNG" squashfs-root/usr/share/anaconda/pixmaps/sidebar-logo.png
    cp -f "$FINAL_TOPBAR_PNG"  squashfs-root/usr/share/anaconda/pixmaps/topbar-logo.png
    sed -i "s/NAME=\"Rocky Linux\"/NAME=\"${DISTRO_NAME}\"/" squashfs-root/etc/os-release
    sed -i "s/Rocky Linux release/${DISTRO_NAME} release/" squashfs-root/etc/redhat-release
    
    # <<< FIX IS HERE >>>
    # Remove the OLD 'install.img' file before repacking
    rm iso_root/images/install.img
    
    # <<< FIX IS HERE >>>
    # Repack the filesystem into a NEW 'install.img' file
    mksquashfs squashfs-root iso_root/images/install.img -noappend > /dev/null || error_exit "Failed to repack install.img."
    
    echo -e "${GREEN}    Visual branding applied.${NC}"

    echo -e "\n${YELLOW}--> Step 6: Integrating Kickstart and configuring bootloader...${NC}"
    cp "$KS_FILENAME" iso_root/
    ISO_LABEL=$(isoinfo -d -i ../"$ISO_FILENAME" | grep "Volume id" | awk -F': ' '{print $2}')
    KS_PARAM="inst.ks=hd:LABEL=${ISO_LABEL}:/${KS_FILENAME}"
    sed -i "/^  linux/ s/$/ ${KS_PARAM}/" iso_root/EFI/BOOT/grub.cfg
    sed -i "/^  append/ s/$/ ${KS_PARAM}/" iso_root/isolinux/isolinux.cfg
    echo -e "${GREEN}    Bootloader configured.${NC}"
    
    echo -e "\n${YELLOW}--> Step 7: Rebuilding final ${BUILD_MODE} ISO...${NC}"
    cd iso_root
    xorriso -as mkisofs -V "${ISO_LABEL}" -o "../../${FINAL_ISO_NAME}" \
      -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
      -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot \
      -boot-load-size 4 -boot-info-table -eltorito-alt-boot \
      -e images/efiboot.img -no-emul-boot -isohybrid-gpt-basdat \
      . > /dev/null 2>&1 || error_exit "Failed to rebuild final ISO."
    cd ../..; rm -rf "$BUILD_DIR"
    
    # Success
    echo -e "\n${GREEN}======================================================================${NC}"
    echo -e "${GREEN}  BUILD COMPLETE!                                                     ${NC}"
    echo -e "${GREEN}  Your '${BUILD_MODE}' ArttulOS installer is ready:                   ${NC}"
    echo -e "${YELLOW}  $(pwd)/${FINAL_ISO_NAME}${NC}"
    echo -e "${GREEN}======================================================================${NC}"
}

main "$@"
