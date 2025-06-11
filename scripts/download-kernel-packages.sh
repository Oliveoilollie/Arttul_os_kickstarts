#!/bin/bash

# ==============================================================================
# ArttulOS - ONLINE Package Downloader
#
# Version: 1.1
#
# Description:
# This script MUST be run on a Linux machine WITH an internet connection.
# Its only purpose is to download the ELRepo mainline kernel RPMs and their
# dependencies into a local directory ('local-rpms').
#
# Once you have this folder, you can move it to your offline build machine
# along with the main build script.
# ==============================================================================

set -e

# --- Configuration ---
RPM_DIR="local-rpms"

# --- Functions ---
print_msg() {
    local color=$1
    local message=$2
    case "$color" in
        "green") echo -e "\n\e[32m[SUCCESS]\e[0m ${message}" ;;
        "blue") echo -e "\n\e[34m[INFO]\e[0m ${message}" ;;
    esac
}

# --- Main Script ---
if [ "$EUID" -ne 0 ]; then
  echo "This script needs to be run with sudo to install the elrepo-release package."
  exit 1
fi

print_msg "blue" "Creating directory for local RPMs: ${RPM_DIR}"
mkdir -p "${RPM_DIR}"

print_msg "blue" "Installing ELRepo release package to enable the repository..."
dnf install -y https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm

print_msg "blue" "Updating DNF cache to recognize the new repository..."
dnf makecache

print_msg "blue" "Downloading mainline kernel packages and dependencies into '${RPM_DIR}'..."
dnf download --enablerepo=elrepo-kernel --resolve --arch=x86_64 \
--downloaddir="${RPM_DIR}" \
kernel-ml kernel-ml-devel

print_msg "green" "Package download complete!"
echo "The folder '${RPM_DIR}' now contains all necessary kernel packages."
echo "You can now copy this entire project directory (including the '${RPM_DIR}' folder)"
echo "to your offline machine and run the main 'build-arttulos-iso.sh' script."