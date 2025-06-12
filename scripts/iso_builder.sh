#!/bin/bash
# ==============================================================================
# ArttulOS ISO Build Script (FINAL v6.0 - Optimized & Refined)
#
# Description:
# - This script automates the creation of a custom Rocky Linux 9 based ISO.
# - It reliably finds and modifies the package group metadata (comps.xml) by
#   reading the ISO's .treeinfo file, resolving kernel dependency conflicts.
# - It injects a custom kernel, branding, and a zero-touch kickstart file.
# - It has been optimized for robustness, readability, and maintainability.
# ==============================================================================

set -e
# Ensure that script commands are run from the script's directory
cd "$(dirname "$0")"

# --- Configuration ---
# Build & File Configuration
PREP_KERNEL_DIR="local-rpms"
PREP_TOOLS_DIR="build-tools-rpms"
BUILD_DIR="arttulos-build"
ISO_EXTRACT_DIR="${BUILD_DIR}/iso_extracted"
CUSTOM_REPO_DIR="${ISO_EXTRACT_DIR}/custom_repo"
WALLPAPER_FILE="strix.png"
FINAL_ISO_NAME="ArttulOS-9-GNOME-Branded-Installer.iso"
ISO_LABEL="ARTTULOS9"
FINAL_ISO_PATH="${PWD}/${FINAL_ISO_NAME}"

# Kickstart Configuration
KS_USER="arttulos"
KS_PASS="arttulos"
KS_HOSTNAME="arttulos.localdomain"
KS_TIMEZONE="America/Los_Angeles"

# --- Functions ---

#
# Prints a formatted message to the console.
#
print_msg() {
    local color=$1
    local message=$2
    case "$color" in
        "green")  echo -e "\n\e[32m[SUCCESS]\e[0m ${message}" ;;
        "blue")   echo -e "\n\e[34m[INFO]\e[0m ${message}" ;;
        "yellow") echo -e "\n\e[33m[WARN]\e[0m ${message}" ;;
        "red")    echo -e "\n\e[31m[ERROR]\e[0m ${message}" >&2 ;;
    esac
}

#
# Cleans up all build artifacts and unmounts directories.
#
cleanup() {
    print_msg "blue" "Cleaning up..."
    # In case of error, the mount might still be active
    umount "${BUILD_DIR}/iso_mount" &>/dev/null || true
    rm -rf "${BUILD_DIR}"
}

#
# Checks for root privileges and required files.
#
initial_checks() {
    if [ "$EUID" -ne 0 ]; then
      print_msg "red" "This script must be run as root. Please use sudo."
      exit 1
    fi

    if [ ! -f "${WALLPAPER_FILE}" ]; then
        print_msg "red" "Branding file not found. Please place '${WALLPAPER_FILE}' in the script's directory."
        exit 1
    fi
}

#
# Checks for and installs required build tools.
#
check_dependencies() {
    local missing_cmds=()
    local required_cmds=(xorriso createrepo_c gunzip sed)

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
        fi
    done

    # isohybrid needs a specific file from syslinux
    if [ ! -f /usr/share/syslinux/isohdpfx.bin ]; then
        missing_cmds+=("syslinux")
    fi

    if [ ${#missing_cmds[@]} -ne 0 ]; then
        print_msg "yellow" "Build tools are missing: ${missing_cmds[*]}. Attempting to install from local cache..."
        if [ ! -d "${PREP_TOOLS_DIR}" ] || [ -z "$(ls -A "${PREP_TOOLS_DIR}"/*.rpm 2>/dev/null)" ]; then
            print_msg "red" "The '${PREP_TOOLS_DIR}' directory is missing or empty. Cannot install dependencies."
            exit 1
        fi
        dnf install -y ./${PREP_TOOLS_DIR}/*.rpm
        print_msg "green" "Build tools installed."
    fi

    if [ ! -d "${PREP_KERNEL_DIR}" ] || [ -z "$(ls -A "${PREP_KERNEL_DIR}"/*.rpm 2>/dev/null)" ]; then
        print_msg "red" "The '${PREP_KERNEL_DIR}' directory with custom kernel RPMs is missing or empty."
        exit 1
    fi
}

#
# Mounts and extracts the source ISO to a working directory.
#
extract_iso() {
    local base_iso_path
    read -p "Please enter the full path to the official Rocky Linux 9 DVD ISO file: " base_iso_path
    if [ ! -f "$base_iso_path" ]; then
        print_msg "red" "ISO file not found at '${base_iso_path}'."
        exit 1
    fi

    print_msg "blue" "Creating build workspace..."
    mkdir -p "${BUILD_DIR}/iso_mount" "${ISO_EXTRACT_DIR}" "${CUSTOM_REPO_DIR}"

    print_msg "blue" "Mounting and extracting the base ISO..."
    mount -o loop,ro "$base_iso_path" "${BUILD_DIR}/iso_mount"
    rsync -a -H --exclude=TRANS.TBL "${BUILD_DIR}/iso_mount/" "${ISO_EXTRACT_DIR}"
    umount "${BUILD_DIR}/iso_mount"
    chmod -R u+w "${ISO_EXTRACT_DIR}"
}

#
# Finds the comps.xml file, removes kernel dependencies, and rebuilds the repo.
#
patch_repository() {
    print_msg "blue" "Locating and patching repository group metadata..."
    local treeinfo_path="${ISO_EXTRACT_DIR}/.treeinfo"
    if [ ! -f "$treeinfo_path" ]; then
        print_msg "red" "CRITICAL: .treeinfo file not found at the root of the ISO. Cannot proceed."
        exit 1
    fi

    # Reliably parse the .treeinfo file to find the path to the groups file.
    local comps_path_relative
    comps_path_relative=$(sed -n '/\[variant-AppStream\]/,/\[/ { /groups =/ s/.*= //p }' "$treeinfo_path")
    if [ -z "$comps_path_relative" ]; then
        print_msg "red" "CRITICAL: Could not parse the groups file path from .treeinfo."
        exit 1
    fi

    local comps_path_full="${ISO_EXTRACT_DIR}/${comps_path_relative}"
    if [ ! -f "$comps_path_full" ]; then
        print_msg "red" "CRITICAL: .treeinfo pointed to a groups file at ${comps_path_full}, but it does not exist."
        exit 1
    fi

    print_msg "green" "Successfully located groups file: ${comps_path_full}"
    local modified_comps_xml="${BUILD_DIR}/comps.xml"

    # Modify a copy of the comps file, not the original.
    cp "$comps_path_full" "$modified_comps_xml"

    print_msg "blue" "Removing mandatory kernel dependencies from groups file..."
    sed -i -e '/<packagereq type="mandatory">kernel<\/packagereq>/d' \
           -e '/<packagereq type="default">kernel<\/packagereq>/d' \
           -e '/<packagereq type="mandatory">kernel-core<\/packagereq>/d' \
           -e '/<packagereq type="default">kernel-core<\/packagereq>/d' \
           "$modified_comps_xml"

    print_msg "yellow" "Deleting old AppStream repodata..."
    rm -rf "${ISO_EXTRACT_DIR}/AppStream/repodata"

    print_msg "blue" "Rebuilding AppStream repository with patched group data..."
    createrepo_c -g "$modified_comps_xml" "${ISO_EXTRACT_DIR}/AppStream"
    print_msg "green" "AppStream repository rebuilt. Package conflict resolved."
}

#
# Creates the custom repository for the new kernel.
#
create_custom_repo() {
    print_msg "blue" "Creating custom kernel repository..."
    cp "${PREP_KERNEL_DIR}"/*.rpm "${CUSTOM_REPO_DIR}/"
    createrepo_c "${CUSTOM_REPO_DIR}"
}

#
# Injects branding files into the ISO structure.
#
inject_branding() {
    print_msg "blue" "Injecting branding assets..."
    mkdir -p "${ISO_EXTRACT_DIR}/branding"
    cp "${WALLPAPER_FILE}" "${ISO_EXTRACT_DIR}/branding/"
}

#
# Generates the kickstart configuration file.
#
create_kickstart() {
    print_msg "blue" "Generating Kickstart file..."
    # Note: Using a quoted heredoc (<< 'EOF') is crucial. It prevents the shell
    # from expanding variables like $SYSTEM_WALLPAPER_DIR at build time. They
    # must be expanded by the Anaconda installer on the target system.
    cat << EOF > "${ISO_EXTRACT_DIR}/ks.cfg"
# Kickstart file for ArttulOS (Fully Automated Zero-Touch Installation)
graphical
eula --agreed
reboot
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone ${KS_TIMEZONE} --isUtc
network --onboot=yes --device=eth0 --bootproto=dhcp --ipv6=auto --activate
network --hostname=${KS_HOSTNAME}
firewall --enabled --service=ssh
selinux --enforcing
zerombr
clearpart --all --initlabel
autopart --type=lvm
bootloader --location=mbr

# User and Root configuration
rootpw --plaintext ${KS_PASS}
user --name=${KS_USER} --groups=wheel --password=${KS_PASS} --plaintext

# Repository Configuration
repo --name="BaseOS" --baseurl=file:///run/install/repo/BaseOS
repo --name="AppStream" --baseurl=file:///run/install/repo/AppStream
repo --name="custom-kernel" --baseurl=file:///run/install/repo/custom_repo

%packages --instLangs=en_US --excludedocs
# The repo metadata is fixed, so we can use a clean package list.
@core
@fonts
@gnome-desktop
@guest-desktop-agents

# Install our custom mainline kernel
kernel-ml
kernel-ml-devel

# Other useful packages
policycoreutils-python-utils
vim-enhanced
kexec-tools
plymouth-scripts
flatpak
curl

# Explicitly remove Rocky Linux logo packages
-rocky-logos
-rocky-logos-httpd
-rocky-logos-epel
%end

%post --log=/root/ks-post.log
echo "--- ArttulOS Post-Installation Script ---"

# Grant passwordless sudo to the wheel group
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# Create custom OS release files
echo "Creating /etc/os-release and /etc/redhat-release..."
cat << 'OS_RELEASE_EOF' > /etc/os-release
NAME="ArttulOS"
VERSION="9"
ID="arttulos"
ID_LIKE="fedora rhel"
VERSION_ID="9"
PLATFORM_ID="platform:el9"
PRETTY_NAME="ArttulOS 9"
ANSI_COLOR="0;35"
CPE_NAME="cpe:/o:arttulos:arttulos:9"
HOME_URL="https://arttulos.com/"
BUG_REPORT_URL="https://bugs.arttulos.com/"
OS_RELEASE_EOF
echo "ArttulOS release 9" > /etc/redhat-release

# Setup wallpapers and themes
INSTALLER_BRANDING_DIR="/run/install/repo/branding"
SYSTEM_WALLPAPER_DIR="/usr/share/backgrounds/arttulos"
mkdir -p \$SYSTEM_WALLPAPER_DIR
cp "\${INSTALLER_BRANDING_DIR}/${WALLPAPER_FILE}" "\${SYSTEM_WALLPAPER_DIR}/"

# Setup Plymouth (boot splash) theme
echo "Configuring Plymouth theme..."
PLYMOUTH_THEME_DIR="/usr/share/plymouth/themes/arttulos"
mkdir -p \$PLYMOUTH_THEME_DIR
cp "\${SYSTEM_WALLPAPER_DIR}/${WALLPAPER_FILE}" "\${PLYMOUTH_THEME_DIR}/"
cat << 'PLYMOUTH_EOF' > \${PLYMOUTH_THEME_DIR}/arttulos.plymouth
[Plymouth Theme]
Name=ArttulOS
Description=ArttulOS Boot Splash
ModuleName=script
[script]
ImageDir=\${PLYMOUTH_THEME_DIR}
ScriptFile=\${PLYMOUTH_THEME_DIR}/arttulos.script
PLYMOUTH_EOF
cat << 'SCRIPT_EOF' > \${PLYMOUTH_THEME_DIR}/arttulos.script
wallpaper_image = Image("${WALLPAPER_FILE}");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
resized_wallpaper_image = wallpaper_image.Scale(screen_width, screen_height);
wallpaper_sprite = Sprite(resized_wallpaper_image);
wallpaper_sprite.SetZ(-100);
SCRIPT_EOF
plymouth-set-default-theme arttulos -R

# Setup GRUB theme
echo "Configuring GRUB theme..."
GRUB_THEME_DIR="/boot/grub2/themes/arttulos"
mkdir -p \$GRUB_THEME_DIR
cp "\${SYSTEM_WALLPAPER_DIR}/${WALLPAPER_FILE}" "\${GRUB_THEME_DIR}/background.png"
cat << 'THEME_EOF' > \${GRUB_THEME_DIR}/theme.txt
desktop-image: "background.png"
desktop-color: "#000000"
title-text: ""
+ boot_menu { left = 15%; width = 70%; top = 35%; height = 40%; item_font = "DejaVu Sans 16"; item_color = "#87cefa"; item_spacing = 25; selected_item_font = "DejaVu Sans Bold 16"; selected_item_color = "#d8b6ff"; }
+ hbox { left = 15%; top = 80%; width = 70%; + label { text = "ArttulOS 9 - Mainline Kernel"; font = "DejaVu Sans 12"; color = "#cccccc"; } }
THEME_EOF
echo 'GRUB_THEME="/boot/grub2/themes/arttulos/theme.txt"' >> /etc/default/grub
echo 'GRUB_TERMINAL_OUTPUT="gfxterm"' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

# Configure GNOME Desktop defaults (Dark Mode and Wallpaper)
echo "Configuring GNOME desktop defaults..."
GSETTINGS_OVERRIDES_DIR="/etc/dconf/db/local.d"
GDM_OVERRIDES_DIR="/etc/dconf/db/gdm.d"
WALLPAPER_PATH="/usr/share/backgrounds/arttulos/${WALLPAPER_FILE}"
mkdir -p \$GSETTINGS_OVERRIDES_DIR \$GDM_OVERRIDES_DIR

# Set defaults for user sessions
cat << 'GSETTINGS_EOF' > \${GSETTINGS_OVERRIDES_DIR}/01-arttulos-branding
[org/gnome/desktop/interface]
# Set dark mode for GTK applications
color-scheme='prefer-dark'
[org/gnome/desktop/background]
picture-uri='file://\${WALLPAPER_PATH}'
picture-uri-dark='file://\${WALLPAPER_PATH}'
[org/gnome/desktop/screensaver]
picture-uri='file://\${WALLPAPER_PATH}'
GSETTINGS_EOF

# Set defaults for the GDM login screen
cat << 'GDM_EOF' > \${GDM_OVERRIDES_DIR}/01-arttulos-branding
[org/gnome/desktop/background]
picture-uri='file://\${WALLPAPER_PATH}'
picture-uri-dark='file://\${WALLPAPER_PATH}'
GDM_EOF
dconf update

# First-boot service for online installations
echo "Setting up first-boot online installation service..."
cat << 'SERVICE_SCRIPT_EOF' > /usr/local/sbin/arttulos-first-boot-setup.sh
#!/bin/bash
# Log all output from this script
exec 1>>/var/log/arttulos-first-boot.log 2>&1
echo "--- Starting first-boot online application installation ---"

# Add flathub and install apps
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.mozilla.firefox org.gajim.Gajim org.gnome.Polari

# Install Nix package manager and an application with it
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --no-daemon --yes

# The Nix installer creates this profile script. We source it to make nix commands available.
if [ -f /root/.nix-profile/etc/profile.d/nix.sh ]; then
    . /root/.nix-profile/etc/profile.d/nix.sh
    nix-env -iA nixpkgs.element-desktop
else
    echo "ERROR: Nix profile script not found. Could not install Element-Desktop."
fi

echo "--- First-boot setup complete. Service will now be disabled. ---"
SERVICE_SCRIPT_EOF

chmod +x /usr/local/sbin/arttulos-first-boot-setup.sh

cat << 'SERVICE_EOF' > /etc/systemd/system/arttulos-first-boot.service
[Unit]
Description=ArttulOS First-Boot Online Application Installer
# Run after the network is confirmed to be online
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/arttulos-first-boot-setup.sh
# Clean up after successful execution
ExecStartPost=/bin/rm -f /usr/local/sbin/arttulos-first-boot-setup.sh
ExecStartPost=/bin/systemctl disable arttulos-first-boot.service

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl enable arttulos-first-boot.service
echo "--- Post-installation script finished. ---"
%end
EOF
}

#
# Patches the bootloader configs for automated kickstart installation.
#
patch_bootloader() {
    print_msg "blue" "Patching bootloader configs for automated installation..."
    local isolinux_cfg="${ISO_EXTRACT_DIR}/isolinux/isolinux.cfg"
    local grub_cfg="${ISO_EXTRACT_DIR}/EFI/BOOT/grub.cfg"
    local ks_append="inst.stage2=hd:LABEL=${ISO_LABEL} quiet inst.ks=hd:LABEL=${ISO_LABEL}:/ks.cfg inst.gtk.theme=Adwaita-dark"

    cat << EOF > "${isolinux_cfg}"
default vesamenu.c32
timeout 10
menu title ArttulOS 9 Installer
label install
  menu label ^Install ArttulOS
  menu default
  kernel vmlinuz
  append initrd=initrd.img ${ks_append}
EOF

    cat << EOF > "${grub_cfg}"
set timeout=1
menuentry 'Install ArttulOS' --class gnu-linux --class gnu --class os {
linuxefi /images/pxeboot/vmlinuz ${ks_append}
initrdefi /images/pxeboot/initrd.img
}
EOF
}

#
# Builds the final, bootable ISO file.
#
build_final_iso() {
    print_msg "blue" "Building the final ISO file..."
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

    # Return ownership to the original user who invoked sudo
    # This is more robust than using `logname`.
    if [ -n "$SUDO_USER" ]; then
        chown "${SUDO_USER}:${SUDO_GROUP:-$SUDO_USER}" "${FINAL_ISO_PATH}"
    fi

    print_msg "green" "Build complete!"
    echo -e "Your new ISO is located at: \e[1m${FINAL_ISO_PATH}\e[0m"
}


# --- Main Script Execution ---
main() {
    trap cleanup EXIT SIGHUP SIGINT SIGTERM
    initial_checks
    check_dependencies
    cleanup # Run once at the start to ensure a clean state
    extract_iso
    patch_repository
    create_custom_repo
    inject_branding
    create_kickstart
    patch_bootloader
    build_final_iso
}

main "$@"
