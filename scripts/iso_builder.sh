#!/bin/bash
# ==============================================================================
# Rocky Linux 9 "Appliance Style" ISO Builder (v3.0)
#
# Author: RHEL/Rocky Linux Engineering Discipline (Modified for User Experience)
#
# Description:
# This script builds an automated Rocky Linux 9 installer that hides verbose
# text output to provide a cleaner, more user-friendly experience.
#
# v3.0 Changes:
#   - Switches to a fully automated GRAPHICAL installation. This naturally hides
#     the text console and shows a user-friendly progress bar instead.
#   - Adds the required package groups for a minimal graphical desktop (Workstation).
#   - The user sees a loading screen and then a progress bar, with no interaction needed.
# ==============================================================================

set -e -o pipefail

# --- Configuration Section ---
readonly FINAL_ISO_NAME="Rocky-9-Appliance-Installer.iso"
readonly KS_FILENAME="rocky9-appliance.ks"

# Kickstart User and System Configuration
readonly KS_LANG="en_US.UTF-8"
readonly KS_TIMEZONE="America/Los_Angeles"
readonly KS_USER="arttulos"
readonly KS_PASS="arttulos"
readonly KS_HOSTNAME="rocky9-desktop.localdomain"

# --- Helper Functions ---
print_msg() {
    local color=$1; local message=$2; local nocolor='\033[0m'
    case "$color" in
        "green")  echo -e "\n\033[1;32m[SUCCESS]\033[0m ${message}${nocolor}" ;;
        "blue")   echo -e "\n\033[1;34m[INFO]\033[0m ${message}${nocolor}" ;;
        "red")    echo -e "\n\033[1;31m[ERROR]\033[0m ${message}${nocolor}" >&2 ;;
    esac
}

# --- Main Functions ---

check_prerequisites() {
    print_msg "blue" "Verifying prerequisites..."
    if [[ "$EUID" -ne 0 ]]; then
        print_msg "red" "This script must be run as root. Please use sudo."
        exit 1
    fi
    if ! command -v mkksiso &> /dev/null; then
        print_msg "red" "'mkksiso' not found. Please run: sudo dnf install pykickstart"
        exit 1
    fi
    print_msg "green" "All prerequisites are met."
}

cleanup() {
    print_msg "blue" "Cleaning up temporary Kickstart file..."
    rm -f "${KS_FILENAME}"
}

generate_kickstart() {
    print_msg "blue" "Generating Kickstart file for a graphical installation..."

    cat << EOF > "${KS_FILENAME}"
# Kickstart for Rocky Linux 9 - "Appliance Style" Graphical Install
# Installation will be fully automated with a graphical progress screen.

# --- System Locale and Install Mode ---
# KEY CHANGE: Use graphical mode to hide the text console.
graphical
# Automatically agree to the EULA to prevent the installer from stopping.
eula --agreed
reboot

lang ${KS_LANG}
keyboard --vckeymap=us --xlayouts='us'
timezone ${KS_TIMEZONE} --isUtc

# --- Installation Source ---
cdrom

# --- Network & Firewall ---
network --bootproto=dhcp --device=link --activate --hostname=${KS_HOSTNAME}
# The 'workstation' profile opens ports, but we can keep SSH for admin access.
firewall --enabled --service=ssh

# --- Partitioning ---
zerombr
clearpart --all --initlabel
autopart --type=lvm
bootloader --location=mbr

# --- Authentication & User Setup ---
rootpw --lock
user --name=${KS_USER} --groups=wheel --password=${KS_PASS} --plaintext

# --- Security ---
selinux --enforcing

# --- Package Selection ---
# KEY CHANGE: A graphical installer requires a graphical environment to be installed.
# We will install a minimal GNOME desktop.
%packages --excludedocs --instLangs=en_US
@workstation-product-environment
@guest-desktop-agents

# Optional: Add any other applications you need here.
# firefox
%end

# --- Post-Installation Script ---
%post --log=/root/ks-post.log --erroronfail
echo "--- Starting Rocky 9 Post-Installation Script ---"

# 1. Configure Sudoers
echo "Configuring sudo for the 'wheel' group..."
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# 2. Harden SSH
echo "Hardening SSH: Disabling root login..."
sed -i 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# 3. Set Welcome Message (MOTD)
echo "Setting the Message of the Day (MOTD)..."
cat << MOTD_EOF > /etc/motd

  Welcome to your new Rocky Linux 9 system.

  Default User: ${KS_USER}
  Default Pass: ${KS_PASS}

  SECURITY WARNING:
  Your system was installed with an insecure default password.
  Please change it immediately by running the 'passwd' command in a terminal.

MOTD_EOF

echo "--- Post-installation script finished successfully. ---"
%end
EOF
    print_msg "green" "Kickstart file generated successfully."
}

build_installer_iso() {
    local base_iso_path
    echo ""
    # A graphical install requires more packages, so the DVD ISO is recommended.
    read -p "Please enter the full path to the BASE Rocky Linux 9 DVD INSTALLER ISO: " base_iso_path

    if [ ! -f "$base_iso_path" ]; then
        print_msg "red" "Source ISO file not found at '${base_iso_path}'. Aborting."
        exit 1
    fi

    print_msg "blue" "Starting ISO build with mkksiso. This will embed the Kickstart file."
    mkksiso --ks "${KS_FILENAME}" "${base_iso_path}" "${FINAL_ISO_NAME}"

    print_msg "green" "Build complete!"
    echo -e "Your new appliance installer ISO is located at: \033[1m${PWD}/${FINAL_ISO_NAME}\033[0m"
}

# --- Main Execution ---
main() {
    trap cleanup EXIT SIGHUP SIGINT SIGTERM
    check_prerequisites
    generate_kickstart
    build_installer_iso
}

main "$@"