#!/bin/bash

# ==============================================================================
#  ArttulOS Automated ISO Builder v5.1
#
#  Merges visual branding with unattended Kickstart installation.
#  Package pre-flight checks have been removed by user request.
#
#  Original Concepts & Logic By:
#  - Visual Branding: Natalie Spiva, ArttulOS Project
#  - Appliance Automation: RHEL/Rocky Linux Engineering Discipline
#
#  Combined and Enhanced by the ArttulOS Project.
# ==============================================================================

# --- Shell Colors for Better Readability ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Error Handling ---
error_exit() {
    echo -e "\n${RED}======================= BUILD FAILED =======================${NC}" >&2
    echo -e "${RED}ERROR: $1${NC}" >&2
    echo -e "${RED}Aborting script.${NC}" >&2
    
    if [ -d "$BUILD_DIR" ]; then
        echo -e "${YELLOW}Attempting to clean up temporary files...${NC}"
        rm -rf "$BUILD_DIR"
    fi
    exit 1
}

# --- Configuration Section ---
# Branding & Versioning
DISTRO_NAME="ArttulOS"
ISO_URL="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.6-x86_64-dvd.iso"
ISO_FILENAME=$(basename "$ISO_URL")
DISTRO_VERSION="9.6"

# Final ISO Output Name
FINAL_ISO_NAME="${DISTRO_NAME}-${DISTRO_VERSION}-Automated-Installer.iso"

# Git Repository for Branding Assets
ASSET_REPO_URL="https://github.com/Sprunglesonthehub/arttulos-assets.git"
SOURCE_SIDEBAR_IMAGE="A.png"
SOURCE_TOPBAR_IMAGE="fox.png"

# Kickstart Configuration
KS_FILENAME="arttulos.ks"
KS_LANG="en_US.UTF-8"
KS_TIMEZONE="America/New_York"
KS_HOSTNAME="arttulos-desktop"
KS_USER="arttulos"
KS_PASS="arttulos" # WARNING: Insecure default password

# --- Script Internals ---
BUILD_DIR="build_temp"
ASSET_DIR="arttulos-assets"
FINAL_SIDEBAR_PNG="arttulos-sidebar.png"
FINAL_TOPBAR_PNG="arttulos-topbar.png"

# ============================ MAIN SCRIPT LOGIC ============================

generate_kickstart() {
    echo -e "\n${YELLOW}--> Step 3: Generating Kickstart file for unattended installation...${NC}"
    cat << EOF > "$BUILD_DIR/$KS_FILENAME"
# Kickstart for ArttulOS - Automated Graphical Install
graphical
eula --agreed
reboot
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
user --name=${KS_USER} --groups=wheel --password=${KS_PASS} --plaintext
selinux --enforcing

%packages --excludedocs --instLangs=en_US
@workstation-product-environment
@guest-desktop-agents
# Add any other applications you want pre-installed here:
# firefox
# libreoffice-writer
%end

%post --log=/root/ks-post.log --erroronfail
echo "--- Starting ArttulOS Post-Installation Script ---"
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
sed -i 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
cat << MOTD_EOF > /etc/motd
  Welcome to your new ArttulOS system.

  Default User: ${KS_USER}
  Default Pass: ${KS_PASS}

  SECURITY WARNING:
  Your system was installed with an insecure default password.
  Please change it immediately by running the 'passwd' command.
MOTD_EOF
echo "--- Post-installation script finished successfully. ---"
%end
EOF
    echo -e "${GREEN}    Kickstart file '${KS_FILENAME}' generated successfully.${NC}"
}

main() {
    # --- Banner ---
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}  ArttulOS Automated ISO Builder v5.1                                 ${NC}"
    echo -e "${BLUE}  Combines branding and unattended installation for a true appliance. ${NC}"
    echo -e "${BLUE}======================================================================${NC}"

    # --- Get Base ISO ---
    echo -e "\n${YELLOW}--> Performing pre-flight checks...${NC}"
    if [ ! -f "$ISO_FILENAME" ]; then
        echo -e "${YELLOW}    Base ISO '${ISO_FILENAME}' not found.${NC}"
        read -p "Do you want to download it now? (~9GB) [y/N]: " -n 1 -r REPLY; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            wget -c "$ISO_URL" || error_exit "Download failed."
        else
            error_exit "User aborted. Please provide the base ISO."
        fi
    else
        echo -e "${GREEN}    Found local base ISO: ${ISO_FILENAME}${NC}"
    fi

    # --- Build Process ---
    echo -e "\n${BLUE}Starting the full ArttulOS build process...${NC}"
    rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR" || error_exit "Could not create build directory."
    
    # Step 1: Clone Assets
    echo -e "\n${YELLOW}--> Step 1: Cloning assets from GitHub...${NC}"
    git clone --quiet "$ASSET_REPO_URL" "$BUILD_DIR/$ASSET_DIR" || error_exit "Failed to clone Git repository."
    echo -e "${GREEN}    Assets cloned.${NC}"

    # Step 2: Process Images
    echo -e "\n${YELLOW}--> Step 2: Resizing branding images...${NC}"
    convert "$BUILD_DIR/$ASSET_DIR/$SOURCE_SIDEBAR_IMAGE" -resize 180x230\! "$BUILD_DIR/$FINAL_SIDEBAR_PNG" || error_exit "Failed to process sidebar image."
    convert "$BUILD_DIR/$ASSET_DIR/$SOURCE_TOPBAR_IMAGE" -resize 150x25\! "$BUILD_DIR/$FINAL_TOPBAR_PNG" || error_exit "Failed to process topbar image."
    echo -e "${GREEN}    Images resized successfully.${NC}"
    
    # Step 3: Generate Kickstart
    generate_kickstart

    # Step 4: Extract ISO
    echo -e "\n${YELLOW}--> Step 4: Extracting base ISO contents...${NC}"
    7z x "$ISO_FILENAME" -o"$BUILD_DIR/iso_root" > /dev/null || error_exit "Failed to extract base ISO."
    echo -e "${GREEN}    ISO extracted.${NC}"

    cd "$BUILD_DIR" || error_exit "Could not enter build directory."

    # Step 5: Apply Branding
    echo -e "\n${YELLOW}--> Step 5: Applying visual branding...${NC}"
    unsquashfs iso_root/images/squashfs.img > /dev/null || error_exit "Failed to unpack squashfs.img."
    cp -f "$FINAL_SIDEBAR_PNG" squashfs-root/usr/share/anaconda/pixmaps/sidebar-logo.png
    cp -f "$FINAL_TOPBAR_PNG"  squashfs-root/usr/share/anaconda/pixmaps/topbar-logo.png
    sed -i "s/NAME=\"Rocky Linux\"/NAME=\"${DISTRO_NAME}\"/" squashfs-root/etc/os-release
    sed -i "s/Rocky Linux release/${DISTRO_NAME} release/" squashfs-root/etc/redhat-release
    rm iso_root/images/squashfs.img
    mksquashfs squashfs-root iso_root/images/squashfs.img -noappend > /dev/null || error_exit "Failed to repack squashfs.img."
    echo -e "${GREEN}    Visual branding applied.${NC}"

    # Step 6: Integrate Kickstart and Modify Bootloader
    echo -e "\n${YELLOW}--> Step 6: Integrating Kickstart file for automation...${NC}"
    cp "$KS_FILENAME" iso_root/
    ISO_LABEL=$(isoinfo -d -i ../"$ISO_FILENAME" | grep "Volume id" | awk -F': ' '{print $2}')
    KS_PARAM="inst.ks=hd:LABEL=${ISO_LABEL}:/${KS_FILENAME}"
    
    # Modify UEFI boot config
    sed -i "/^  linux/ s/$/ ${KS_PARAM}/" iso_root/EFI/BOOT/grub.cfg
    # Modify legacy BIOS boot config
    sed -i "/^  append/ s/$/ ${KS_PARAM}/" iso_root/isolinux/isolinux.cfg
    echo -e "${GREEN}    Bootloader configured for unattended install.${NC}"
    
    # Step 7: Rebuild Final ISO
    echo -e "\n${YELLOW}--> Step 7: Rebuilding final automated ISO...${NC}"
    cd iso_root
    xorriso -as mkisofs \
      -V "${ISO_LABEL}" \
      -o "../../${FINAL_ISO_NAME}" \
      -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
      -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot \
      -boot-load-size 4 -boot-info-table -eltorito-alt-boot \
      -e images/efiboot.img -no-emul-boot -isohybrid-gpt-basdat \
      . > /dev/null 2>&1 || error_exit "Failed to rebuild final ISO."
    cd ../..
    rm -rf "$BUILD_DIR"
    
    # --- Success ---
    echo -e "\n${GREEN}======================================================================${NC}"
    echo -e "${GREEN}  BUILD COMPLETE!                                                     ${NC}"
    echo -e "${GREEN}  Your fully automated ArttulOS installer is ready:                   ${NC}"
    echo -e "${YELLOW}  $(pwd)/${FINAL_ISO_NAME}${NC}"
    echo -e "${GREEN}======================================================================${NC}"
}

main "$@"
