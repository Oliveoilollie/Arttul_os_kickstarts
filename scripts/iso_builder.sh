#!/bin/bash
# ==============================================================================
# ArttulOS ISO Build Script (v6.4 - Syntax and Logic Fixes)
#
# Description:
# - Corrects critical shell syntax errors in `cat` command usage. All
#   heredocs now use the proper, multi-line format for robustness.
# - Fixes a logic bug (typo) in the Flatpak repository URL.
# - Retains the enterprise-grade parser for .treeinfo from v6.3.
# ==============================================================================

set -e
# Ensure that script commands are run from the script's directory
cd "$(dirname "$0")"

# --- Configuration ---
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
print_msg() {
    local color=$1; local message=$2
    case "$color" in
        "green")  echo -e "\n\e[32m[SUCCESS]\e[0m ${message}" ;;
        "blue")   echo -e "\n\e[34m[INFO]\e[0m ${message}" ;;
        "yellow") echo -e "\n\e[33m[WARN]\e[0m ${message}" ;;
        "red")    echo -e "\n\e[31m[ERROR]\e[0m ${message}" >&2 ;;
    esac
}
cleanup() {
    print_msg "blue" "Cleaning up..."
    umount "${BUILD_DIR}/iso_mount" &>/dev/null || true
    rm -rf "${BUILD_DIR}"
}
initial_checks() {
    if [ "$EUID" -ne 0 ]; then print_msg "red" "This script must be run as root. Please use sudo."; exit 1; fi
    if [ ! -f "${WALLPAPER_FILE}" ]; then print_msg "red" "Branding file not found: '${WALLPAPER_FILE}'"; exit 1; fi
}
check_dependencies() {
    local missing_cmds=(); local required_cmds=(xorriso createrepo_c gunzip sed)
    for cmd in "${required_cmds[@]}"; do if ! command -v "$cmd" &> /dev/null; then missing_cmds+=("$cmd"); fi; done
    if [ ! -f /usr/share/syslinux/isohdpfx.bin ]; then missing_cmds+=("syslinux"); fi
    if [ ${#missing_cmds[@]} -ne 0 ]; then
        print_msg "yellow" "Missing build tools: ${missing_cmds[*]}. Installing from cache..."
        if [ ! -d "${PREP_TOOLS_DIR}" ] || [ -z "$(ls -A "${PREP_TOOLS_DIR}"/*.rpm 2>/dev/null)" ]; then print_msg "red" "'${PREP_TOOLS_DIR}' is missing or empty."; exit 1; fi
        dnf install -y ./${PREP_TOOLS_DIR}/*.rpm; print_msg "green" "Build tools installed."
    fi
    if [ ! -d "${PREP_KERNEL_DIR}" ] || [ -z "$(ls -A "${PREP_KERNEL_DIR}"/*.rpm 2>/dev/null)" ]; then print_msg "red" "'${PREP_KERNEL_DIR}' is missing or empty."; exit 1; fi
}
extract_iso() {
    local base_iso_path
    read -p "Please enter the full path to the official Rocky Linux 9 DVD ISO file: " base_iso_path
    if [ ! -f "$base_iso_path" ]; then print_msg "red" "ISO file not found: '${base_iso_path}'."; exit 1; fi
    print_msg "blue" "Creating build workspace..."; mkdir -p "${BUILD_DIR}/iso_mount" "${ISO_EXTRACT_DIR}" "${CUSTOM_REPO_DIR}"
    print_msg "blue" "Mounting and extracting the base ISO..."; mount -o loop,ro "$base_iso_path" "${BUILD_DIR}/iso_mount"
    rsync -a -H --exclude=TRANS.TBL "${BUILD_DIR}/iso_mount/" "${ISO_EXTRACT_DIR}"; umount "${BUILD_DIR}/iso_mount"; chmod -R u+w "${ISO_EXTRACT_DIR}"
}
patch_repository() {
    print_msg "blue" "Parsing .treeinfo to locate repository group metadata..."
    local treeinfo_path="${ISO_EXTRACT_DIR}/.treeinfo"
    if [ ! -f "$treeinfo_path" ]; then
        print_msg "red" "CRITICAL: .treeinfo file not found at the root of the ISO. Cannot proceed."
        exit 1
    fi
    local comps_path_relative=""
    local in_appstream_section=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[.*AppStream.*\]$ ]]; then
            in_appstream_section=true
            continue
        fi
        if [ "$in_appstream_section" = true ]; then
            if [[ "$line" =~ ^\[.*\]$ ]]; then
                in_appstream_section=false
                break
            fi
            if [[ "$line" =~ ^groups[[:space:]]*= ]]; then
                comps_path_relative=$(echo "$line" | cut -d '=' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                break
            fi
        fi
    done < "$treeinfo_path"
    if [ -z "$comps_path_relative" ]; then
        print_msg "red" "CRITICAL: The parser could not find a 'groups =' entry within an [AppStream] section in the .treeinfo file."
        print_msg "red" "Please inspect '${treeinfo_path}' manually."
        exit 1
    fi
    local comps_path_full="${ISO_EXTRACT_DIR}/${comps_path_relative}"
    if [ ! -f "$comps_path_full" ]; then
        print_msg "red" "CRITICAL: .treeinfo pointed to a groups file at '${comps_path_full}', but it does not exist."
        exit 1
    fi
    print_msg "green" "Successfully located groups (comps) file: ${comps_path_full}"
    local modified_comps_xml="${BUILD_DIR}/comps.xml"; cp "$comps_path_full" "$modified_comps_xml"
    print_msg "blue" "Removing kernel dependencies from group metadata..."; sed -i -e '/<packagereq type="mandatory">kernel<\/packagereq>/d' -e '/<packagereq type="default">kernel<\/packagereq>/d' -e '/<packagereq type="mandatory">kernel-core<\/packagereq>/d' -e '/<packagereq type="default">kernel-core<\/packagereq>/d' "$modified_comps_xml"
    print_msg "yellow" "Deleting old AppStream repodata..."; rm -rf "${ISO_EXTRACT_DIR}/AppStream/repodata"
    print_msg "blue" "Rebuilding AppStream repository with modified group data..."; createrepo_c -g "$modified_comps_xml" "${ISO_EXTRACT_DIR}/AppStream"; print_msg "green" "AppStream repository rebuilt successfully."
}
create_custom_repo() {
    print_msg "blue" "Creating custom kernel repository..."; cp "${PREP_KERNEL_DIR}"/*.rpm "${CUSTOM_REPO_DIR}/"; createrepo_c "${CUSTOM_REPO_DIR}"
}
inject_branding() {
    print_msg "blue" "Injecting branding assets..."; mkdir -p "${ISO_EXTRACT_DIR}/branding"; cp "${WALLPAPER_FILE}" "${ISO_EXTRACT_DIR}/branding/"
}

#
# Generates the kickstart file. All sub-heredocs are now correctly formatted.
#
create_kickstart() {
    print_msg "blue" "Generating Kickstart file..."
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

%post --log=/root/ks-post.log
echo "--- ArttulOS Post-Installation & Full Rebranding Script ---"
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

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
echo "Branding TTY login prompts (/etc/issue)..."
echo "ArttulOS 9" > /etc/issue
echo "ArttulOS 9 -- Kernel \\r on \\m" > /etc/issue.net
echo "Rebranding DNF repository files..."
for repo_file in /etc/yum.repos.d/rocky*.repo; do
    if [ -f "\$repo_file" ]; then
        new_name=\$(echo "\$repo_file" | sed 's/rocky/arttulos/')
        mv "\$repo_file" "\$new_name"
        sed -i 's/^name=Rocky Linux/name=ArttulOS/g' "\$new_name"
    fi
done
INSTALLER_BRANDING_DIR="/run/install/repo/branding"
SYSTEM_WALLPAPER_DIR="/usr/share/backgrounds/arttulos"
mkdir -p \$SYSTEM_WALLPAPER_DIR; cp "\${INSTALLER_BRANDING_DIR}/${WALLPAPER_FILE}" "\${SYSTEM_WALLPAPER_DIR}/"
PLYMOUTH_THEME_DIR="/usr/share/plymouth/themes/arttulos"
mkdir -p \$PLYMOUTH_THEME_DIR; cp "\${SYSTEM_WALLPAPER_DIR}/${WALLPAPER_FILE}" "\${PLYMOUTH_THEME_DIR}/"

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
GRUB_THEME_DIR="/boot/grub2/themes/arttulos"
mkdir -p \$GRUB_THEME_DIR; cp "\${SYSTEM_WALLPAPER_DIR}/${WALLPAPER_FILE}" "\${GRUB_THEME_DIR}/background.png"

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
echo "Configuring GNOME desktop defaults..."
GSETTINGS_OVERRIDES_DIR="/etc/dconf/db/local.d"
GDM_OVERRIDES_DIR="/etc/dconf/db/gdm.d"
WALLPAPER_PATH="/usr/share/backgrounds/arttulos/${WALLPAPER_FILE}"
mkdir -p \$GSETTINGS_OVERRIDES_DIR \$GDM_OVERRIDES_DIR

cat << 'GSETTINGS_EOF' > \${GSETTINGS_OVERRIDES_DIR}/01-arttulos-branding
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
[org/gnome/desktop/background]
picture-uri='file://\${WALLPAPER_PATH}'
picture-uri-dark='file://\${WALLPAPER_PATH}'
[org/gnome/desktop/screensaver]
picture-uri='file://\${WALLPAPER_PATH}'
GSETTINGS_EOF

cat << 'GDM_EOF' > \${GDM_OVERRIDES_DIR}/01-arttulos-branding
[org/gnome/desktop/background]
picture-uri='file://\${WALLPAPER_PATH}'
picture-uri-dark='file://\${WALLPAPER_PATH}'
GDM_EOF

cat << 'GSETTINGS_FAV_EOF' > \${GSETTINGS_OVERRIDES_DIR}/02-arttulos-favorites
[org.gnome.shell]
favorite-apps=['org.mozilla.firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Console.desktop', 'org.gnome.Software.desktop']
GSETTINGS_FAV_EOF

dconf update

cat << 'SERVICE_SCRIPT_EOF' > /usr/local/sbin/arttulos-first-boot-setup.sh
#!/bin/bash
exec 1>>/var/log/arttulos-first-boot.log 2>&1
echo "--- Starting first-boot online application installation ---"
# CRITICAL FIX: Corrected URL from dl.flub.org to dl.flathub.org
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.mozilla.firefox org.gajim.Gajim org.gnome.Polari
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --no-daemon --yes
if [ -f /root/.nix-profile/etc/profile.d/nix.sh ]; then
    . /root/.nix-profile/etc/profile.d/nix.sh
    nix-env -iA nixpkgs.element-desktop
else
    echo "ERROR: Nix profile script not found. Could not install Element-Desktop."
fi
echo "--- First-boot setup complete ---"
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
echo "--- Post-installation script finished. ---"
%end
EOF
}

#
# Patches bootloader configs using proper, multi-line heredocs.
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

build_final_iso() {
    print_msg "blue" "Building the final ISO file..."; cd "${ISO_EXTRACT_DIR}"
    xorriso -as mkisofs -V "${ISO_LABEL}" -o "${FINAL_ISO_PATH}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efiboot.img -no-emul-boot -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin .
    cd ..; if [ -n "$SUDO_USER" ]; then chown "${SUDO_USER}:${SUDO_GROUP:-$SUDO_USER}" "${FINAL_ISO_PATH}"; fi
    print_msg "green" "Build complete!"; echo -e "Your new ISO is located at: \e[1m${FINAL_ISO_PATH}\e[0m"
}

# --- Main Script Execution ---
main() {
    trap cleanup EXIT SIGHUP SIGINT SIGTERM
    initial_checks
    check_dependencies
    cleanup 
    extract_iso
    patch_repository
    create_custom_repo
    inject_branding
    create_kickstart
    patch_bootloader
    build_final_iso
}

main "$@"
