#!/bin/bash
# ==============================================================================
# ArttulOS ISO Build Script (v7.0 - Clean Architecture)
#
# Author: RHEL/Rocky Linux Engineering Discipline
#
# Description:
# This script builds a fully branded and customized ArttulOS installation ISO
# from an official Rocky Linux 9 base. It is architected for robustness,
# clarity, and long-term maintainability.
#
# Features:
#   - Robust .treeinfo parser to find and patch AppStream group metadata.
#   - Complete system rebranding (GRUB, Plymouth, DNF repos, OS info, etc.).
#   - Injection of a custom mainline kernel from a local repository.
#   - Fully automated zero-touch installation via a comprehensive Kickstart.
#   - GNOME desktop customization (dark mode, default favorites, wallpaper).
#   - Self-disposing first-boot service for installing online applications.
# ==============================================================================

set -e -o pipefail

# --- Configuration Section ---
# All user-configurable variables are here.

# DIRECTORY & FILE PATHS
# These directories must exist in the same location as the script.
readonly PREP_KERNEL_DIR="local-rpms"     # Contains custom kernel RPMs.
readonly PREP_TOOLS_DIR="build-tools-rpms"  # Contains offline build tool RPMs.
readonly WALLPAPER_FILE="strix.png"       # Branding wallpaper file.

# ISO & BUILD ARTIFACTS
readonly BUILD_DIR="arttulos-build"
readonly FINAL_ISO_NAME="ArttulOS-9-GNOME-Branded-Installer.iso"
readonly ISO_LABEL="ARTTULOS9" # Max 11 characters for ISO9660 Label.

# KICKSTART & SYSTEM DEFAULTS
readonly KS_USER="arttulos"
readonly KS_PASS="arttulos"
readonly KS_HOSTNAME="arttulos.localdomain"
readonly KS_TIMEZONE="America/Los_Angeles"

# --- Helper Functions ---

#
# Prints a formatted, colored message to the console.
#
print_msg() {
    local color=$1
    local message=$2
    local nocolor='\033[0m'
    case "$color" in
        "green")  echo -e "\n\033[1;32m[SUCCESS]\033[0m ${message}${nocolor}" ;;
        "blue")   echo -e "\n\033[1;34m[INFO]\033[0m ${message}${nocolor}" ;;
        "yellow") echo -e "\n\033[1;33m[WARN]\033[0m ${message}${nocolor}" ;;
        "red")    echo -e "\n\033[1;31m[ERROR]\033[0m ${message}${nocolor}" >&2 ;;
    esac
}

#
# Ensures all temporary build artifacts and mounts are removed on exit.
#
cleanup() {
    print_msg "blue" "Performing cleanup..."
    # Unmount may fail if it's not mounted, so we suppress errors.
    umount "${BUILD_DIR}/iso_mount" &>/dev/null || true
    rm -rf "${BUILD_DIR}"
}

# --- Build Step Functions ---

#
# Verifies script prerequisites: root privileges and required input files.
#
check_prerequisites() {
    print_msg "blue" "Verifying prerequisites..."
    if [[ "$EUID" -ne 0 ]]; then
        print_msg "red" "This script must be run as root. Please use sudo."
        exit 1
    fi
    if [ ! -f "${WALLPAPER_FILE}" ]; then
        print_msg "red" "Branding file not found at: '${PWD}/${WALLPAPER_FILE}'"
        exit 1
    fi
    if [ ! -d "${PREP_KERNEL_DIR}" ] || [ -z "$(ls -A "${PREP_KERNEL_DIR}"/*.rpm 2>/dev/null)" ]; then
        print_msg "red" "The '${PREP_KERNEL_DIR}' directory is missing or empty."
        exit 1
    fi
}

#
# Checks for required command-line tools and installs them from the local
# cache if they are missing.
#
install_dependencies() {
    print_msg "blue" "Checking for build dependencies..."
    local missing_pkgs=()
    local required_cmds=(xorriso createrepo_c gunzip sed)

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_pkgs+=("$cmd")
        fi
    done
    if [ ! -f /usr/share/syslinux/isohdpfx.bin ]; then
        missing_pkgs+=("syslinux")
    fi

    if [ ${#missing_pkgs[@]} -ne 0 ]; then
        print_msg "yellow" "Missing dependencies: ${missing_pkgs[*]}. Attempting to install from local cache."
        if [ ! -d "${PREP_TOOLS_DIR}" ] || [ -z "$(ls -A "${PREP_TOOLS_DIR}"/*.rpm 2>/dev/null)" ]; then
            print_msg "red" "The '${PREP_TOOLS_DIR}' directory is missing or empty. Cannot install tools."
            exit 1
        fi
        dnf install -y ./"${PREP_TOOLS_DIR}"/*.rpm
        print_msg "green" "Build dependencies installed successfully."
    else
        print_msg "green" "All build dependencies are present."
    fi
}

#
# Prepares a clean directory structure for the build process.
#
prepare_workspace() {
    print_msg "blue" "Preparing clean build workspace..."
    # The trap will handle cleanup, but we run it once initially for a clean start.
    cleanup
    mkdir -p "${BUILD_DIR}/iso_mount" "${BUILD_DIR}/iso_extracted"
}

#
# Mounts the source ISO and copies its contents to a writable directory.
#
extract_iso() {
    local base_iso_path
    read -p "Please enter the full path to the official Rocky Linux 9 DVD ISO: " base_iso_path
    if [ ! -f "$base_iso_path" ]; then
        print_msg "red" "Source ISO file not found at '${base_iso_path}'."
        exit 1
    fi

    print_msg "blue" "Mounting and extracting base ISO contents..."
    mount -o loop,ro "$base_iso_path" "${BUILD_DIR}/iso_mount"
    rsync -a -H --exclude=TRANS.TBL "${BUILD_DIR}/iso_mount/" "${BUILD_DIR}/iso_extracted"
    umount "${BUILD_DIR}/iso_mount"
    # Make the extracted content writable.
    chmod -R u+w "${BUILD_DIR}/iso_extracted"
    print_msg "green" "ISO extracted successfully."
}

#
# The core fix: finds comps.xml, removes the kernel dependency, and rebuilds
# the AppStream repository to resolve package conflicts.
#
patch_appstream_repo() {
    print_msg "blue" "Patching AppStream repository to remove kernel dependency..."
    local iso_extract_dir="${BUILD_DIR}/iso_extracted"
    local treeinfo_path="${iso_extract_dir}/.treeinfo"

    # Step 1: Robustly parse .treeinfo to find the comps file path.
    local comps_path_relative=""
    local in_appstream_section=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[.*AppStream.*\]$ ]]; then in_appstream_section=true; continue; fi
        if [ "$in_appstream_section" = true ]; then
            if [[ "$line" =~ ^\[.*\]$ ]]; then break; fi
            if [[ "$line" =~ ^groups[[:space:]]*= ]]; then
                comps_path_relative=$(echo "$line" | cut -d '=' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                break
            fi
        fi
    done < "$treeinfo_path"

    if [ -z "$comps_path_relative" ]; then
        print_msg "red" "Failed to parse the 'groups' path from the AppStream section of .treeinfo."
        exit 1
    fi

    local comps_path_full="${iso_extract_dir}/${comps_path_relative}"
    if [ ! -f "$comps_path_full" ]; then
        print_msg "red" ".treeinfo pointed to a comps file that does not exist: '${comps_path_full}'"
        exit 1
    fi
    print_msg "green" "Located groups file: ${comps_path_relative}"

    # Step 2: Modify a copy of the comps file.
    local modified_comps_xml="${BUILD_DIR}/comps.xml"
    cp "$comps_path_full" "$modified_comps_xml"
    sed -i -e '/<packagereq type="mandatory">kernel<\/packagereq>/d' \
           -e '/<packagereq type="default">kernel<\/packagereq>/d' \
           -e '/<packagereq type="mandatory">kernel-core<\/packagereq>/d' \
           -e '/<packagereq type="default">kernel-core<\/packagereq>/d' \
           "$modified_comps_xml"

    # Step 3: Rebuild the repository metadata with the modified groups file.
    local appstream_dir="${iso_extract_dir}/AppStream"
    rm -rf "${appstream_dir}/repodata"
    createrepo_c -g "$modified_comps_xml" "$appstream_dir"
    print_msg "green" "AppStream repository patched and rebuilt successfully."
}

#
# Creates a custom local repository within the ISO for our kernel.
#
create_custom_repo() {
    print_msg "blue" "Creating custom kernel repository..."
    local custom_repo_dir="${BUILD_DIR}/iso_extracted/custom_repo"
    mkdir -p "$custom_repo_dir"
    cp "${PREP_KERNEL_DIR}"/*.rpm "${custom_repo_dir}/"
    createrepo_c "$custom_repo_dir"
    print_msg "green" "Custom repository created."
}

#
# Generates the entire Kickstart file for a zero-touch, branded installation.
#
generate_kickstart() {
    print_msg "blue" "Generating Kickstart configuration file..."
    local iso_extract_dir="${BUILD_DIR}/iso_extracted"

    # Note: Using 'EOF' is critical here to prevent the build host's shell
    # from expanding variables intended for the target system's %post script.
    cat << EOF > "${iso_extract_dir}/ks.cfg"
# Kickstart for ArttulOS 9 - Generated by Build Script v7.0
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
rootpw --plaintext ${KS_PASS}
user --name=${KS_USER} --groups=wheel --password=${KS_PASS} --plaintext
repo --name="BaseOS" --baseurl=file:///run/install/repo/BaseOS
repo --name="AppStream" --baseurl=file:///run/install/repo/AppStream
repo --name="custom-kernel" --baseurl=file:///run/install/repo/custom_repo

%packages --instLangs=en_US --excludedocs
@core
@fonts
@gnome-desktop
@guest-desktop-agents
kernel-ml
kernel-ml-devel
policycoreutils-python-utils
vim-enhanced
kexec-tools
plymouth-scripts
flatpak
curl
-rocky-logos
-rocky-logos-httpd
-rocky-logos-epel
%end

%post --log=/root/ks-post.log --erroronfail
echo "--- ArttulOS Post-Installation & Full Rebranding Script ---"

# System Identity
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
cat << 'OS_RELEASE_EOF' > /etc/os-release
NAME="ArttulOS"; VERSION="9"; ID="arttulos"; ID_LIKE="fedora rhel"; VERSION_ID="9"; PLATFORM_ID="platform:el9"
PRETTY_NAME="ArttulOS 9"; ANSI_COLOR="0;35"; CPE_NAME="cpe:/o:arttulos:arttulos:9"
HOME_URL="https://arttulos.com/"; BUG_REPORT_URL="https://bugs.arttulos.com/"
OS_RELEASE_EOF
echo "ArttulOS release 9" > /etc/redhat-release
echo "ArttulOS 9" > /etc/issue; echo "ArttulOS 9 -- Kernel \\r on \\m" > /etc/issue.net

# DNF Repository Branding
for repo_file in /etc/yum.repos.d/rocky*.repo; do
    [ -f "\$repo_file" ] || continue
    new_name=\$(echo "\$repo_file" | sed 's/rocky/arttulos/')
    mv "\$repo_file" "\$new_name"
    sed -i 's/^name=Rocky Linux/name=ArttulOS/g' "\$new_name"
done

# Visual Branding (Wallpaper, Plymouth, GRUB)
INSTALLER_BRANDING_DIR="/run/install/repo/branding"
SYSTEM_WALLPAPER_DIR="/usr/share/backgrounds/arttulos"
mkdir -p "\${SYSTEM_WALLPAPER_DIR}"
cp "\${INSTALLER_BRANDING_DIR}/${WALLPAPER_FILE}" "\${SYSTEM_WALLPAPER_DIR}/"

PLYMOUTH_THEME_DIR="/usr/share/plymouth/themes/arttulos"
mkdir -p "\${PLYMOUTH_THEME_DIR}"
cp "\${SYSTEM_WALLPAPER_DIR}/${WALLPAPER_FILE}" "\${PLYMOUTH_THEME_DIR}/"
cat << 'PLYMOUTH_EOF' > "\${PLYMOUTH_THEME_DIR}/arttulos.plymouth"
[Plymouth Theme]; Name=ArttulOS; Description=ArttulOS Boot Splash; ModuleName=script
[script]; ImageDir=\${PLYMOUTH_THEME_DIR}; ScriptFile=\${PLYMOUTH_THEME_DIR}/arttulos.script
PLYMOUTH_EOF
cat << 'SCRIPT_EOF' > "\${PLYMOUTH_THEME_DIR}/arttulos.script"
wallpaper_image = Image("${WALLPAPER_FILE}"); screen_width = Window.GetWidth(); screen_height = Window.GetHeight();
resized_wallpaper_image = wallpaper_image.Scale(screen_width, screen_height);
wallpaper_sprite = Sprite(resized_wallpaper_image); wallpaper_sprite.SetZ(-100);
SCRIPT_EOF
plymouth-set-default-theme arttulos -R

GRUB_THEME_DIR="/boot/grub2/themes/arttulos"
mkdir -p "\${GRUB_THEME_DIR}"
cp "\${SYSTEM_WALLPAPER_DIR}/${WALLPAPER_FILE}" "\${GRUB_THEME_DIR}/background.png"
cat << 'THEME_EOF' > "\${GRUB_THEME_DIR}/theme.txt"
desktop-image: "background.png"; desktop-color: "#000000"; title-text: ""
+ boot_menu { left = 15%; width = 70%; top = 35%; height = 40%; item_font = "DejaVu Sans 16"; item_color = "#87cefa"; item_spacing = 25; selected_item_font = "DejaVu Sans Bold 16"; selected_item_color = "#d8b6ff"; }
+ hbox { left = 15%; top = 80%; width = 70%; + label { text = "ArttulOS 9 - Mainline Kernel"; font = "DejaVu Sans 12"; color = "#cccccc"; } }
THEME_EOF
echo 'GRUB_THEME="/boot/grub2/themes/arttulos/theme.txt"' >> /etc/default/grub
echo 'GRUB_TERMINAL_OUTPUT="gfxterm"' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

# GNOME Desktop Configuration
GSETTINGS_OVERRIDES_DIR="/etc/dconf/db/local.d"
WALLPAPER_PATH="file://\${SYSTEM_WALLPAPER_DIR}/${WALLPAPER_FILE}"
mkdir -p "\${GSETTINGS_OVERRIDES_DIR}"
cat << 'GSETTINGS_EOF' > "\${GSETTINGS_OVERRIDES_DIR}/01-arttulos-branding"
[org/gnome/desktop/interface]; color-scheme='prefer-dark'
[org/gnome/desktop/background]; picture-uri='${WALLPAPER_PATH}'; picture-uri-dark='${WALLPAPER_PATH}'
[org/gnome/desktop/screensaver]; picture-uri='${WALLPAPER_PATH}'
[org.gnome.shell]; favorite-apps=['org.mozilla.firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Console.desktop', 'org.gnome.Software.desktop']
GSETTINGS_EOF
dconf update

# First-Boot Service for Online Setups
cat << 'SERVICE_SCRIPT_EOF' > /usr/local/sbin/arttulos-first-boot.sh
#!/bin/bash
exec 1>>/var/log/arttulos-first-boot.log 2>&1
echo "--- Starting first-boot online application installation ---"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.mozilla.firefox org.gajim.Gajim org.gnome.Polari
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --no-daemon --yes
if [ -f /root/.nix-profile/etc/profile.d/nix.sh ]; then
    . /root/.nix-profile/etc/profile.d/nix.sh
    nix-env -iA nixpkgs.element-desktop
fi
echo "--- First-boot setup complete. Service will now be disabled. ---"
SERVICE_SCRIPT_EOF
chmod +x /usr/local/sbin/arttulos-first-boot.sh
cat << 'SERVICE_EOF' > /etc/systemd/system/arttulos-first-boot.service
[Unit]; Description=ArttulOS First-Boot Online Installer; After=network-online.target; Wants=network-online.target
[Service]; Type=oneshot; ExecStart=/usr/local/sbin/arttulos-first-boot.sh; ExecStartPost=/bin/rm -f /usr/local/sbin/arttulos-first-boot.sh; ExecStartPost=/bin/systemctl disable arttulos-first-boot.service
[Install]; WantedBy=multi-user.target
SERVICE_EOF
systemctl enable arttulos-first-boot.service

echo "--- Post-installation script finished successfully. ---"
%end
EOF
    print_msg "green" "Kickstart file generated successfully."
}

#
# Injects branding files and configures the bootloader for automated install.
#
configure_bootloader() {
    print_msg "blue" "Configuring bootloader and injecting branding..."
    local iso_extract_dir="${BUILD_DIR}/iso_extracted"
    
    # Inject branding assets for the installer/live environment
    mkdir -p "${iso_extract_dir}/branding"
    cp "${WALLPAPER_FILE}" "${iso_extract_dir}/branding/"

    # Configure bootloader menus to point to the Kickstart file
    local ks_append="inst.stage2=hd:LABEL=${ISO_LABEL} quiet inst.ks=hd:LABEL=${ISO_LABEL}:/ks.cfg"
    cat << EOF > "${iso_extract_dir}/isolinux/isolinux.cfg"
default vesamenu.c32
timeout 10
menu title ArttulOS 9 Installer
label install
  menu label ^Install ArttulOS
  menu default
  kernel vmlinuz
  append initrd=initrd.img ${ks_append}
EOF
    cat << EOF > "${iso_extract_dir}/EFI/BOOT/grub.cfg"
set timeout=1
menuentry 'Install ArttulOS' --class gnu-linux --class gnu --class os {
    linuxefi /images/pxeboot/vmlinuz ${ks_append}
    initrdefi /images/pxeboot/initrd.img
}
EOF
    print_msg "green" "Bootloader configured for automated Kickstart installation."
}

#
# Builds the final, bootable ISO image using xorriso.
#
build_iso() {
    print_msg "blue" "Building the final ISO image. This may take a while..."
    local iso_extract_dir="${BUILD_DIR}/iso_extracted"
    local final_iso_path="${PWD}/${FINAL_ISO_NAME}"

    cd "$iso_extract_dir"
    xorriso -as mkisofs \
      -V "${ISO_LABEL}" \
      -o "${final_iso_path}" \
      -b isolinux/isolinux.bin \
      -c isolinux/boot.cat \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
      -eltorito-alt-boot \
      -e images/efiboot.img \
      -no-emul-boot \
      -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
      .
    cd ..

    # Return ownership of the created ISO to the user who ran sudo
    if [ -n "$SUDO_USER" ]; then
        chown "${SUDO_USER}:${SUDO_GROUP:-$SUDO_USER}" "${final_iso_path}"
    fi

    print_msg "green" "Build complete!"
    echo -e "Your new ISO is located at: \033[1m${final_iso_path}\033[0m"
}

# --- Main Execution ---

main() {
    # Ensure cleanup runs regardless of script exit status
    trap cleanup EXIT SIGHUP SIGINT SIGTERM

    # Execute build steps in logical order
    check_prerequisites
    install_dependencies
    prepare_workspace
    extract_iso
    patch_appstream_repo
    create_custom_repo
    generate_kickstart
    configure_bootloader
    build_iso
}

# Run the main function, passing all script arguments to it
main "$@"
