#!/bin/bash

# ==============================================================================
# ArttulOS - Ultimate Dependency Downloader (ONLINE)
#
# Version: 4.0 - Uses xorriso and the correct syslinux MBR.
#
# Description:
# Downloads EVERYTHING needed for the offline build process:
#   1. The ELRepo mainline kernel packages into './local-rpms/'.
#   2. The ISO build tools: xorriso, createrepo_c, and syslinux.
# ==============================================================================

set -e

# --- Configuration ---
KERNEL_RPM_DIR="local-rpms"
TOOLS_RPM_DIR="build-tools-rpms"

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

print_msg "blue" "Creating directories for all local RPMs..."
mkdir -p "${KERNEL_RPM_DIR}"
mkdir -p "${TOOLS_RPM_DIR}"

print_msg "blue" "Installing ELRepo release package to enable the repository..."
dnf install -y https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm

print_msg "blue" "Updating DNF cache..."
dnf makecache

print_msg "blue" "Downloading mainline kernel packages into '${KERNEL_RPM_DIR}'..."
dnf download --enablerepo=elrepo-kernel --resolve --arch=x86_64 \
--downloaddir="${KERNEL_RPM_DIR}" \
kernel-ml kernel-ml-devel

print_msg "blue" "Downloading ISO build tools into '${TOOLS_RPM_DIR}'..."
# We need xorriso, createrepo_c, and syslinux (for the MBR).
dnf download --resolve --arch=x86_64 \
--downloaddir="${TOOLS_RPM_DIR}" \
xorriso createrepo_c syslinux

print_msg "green" "All downloads complete!"
echo "The folders '${KERNEL_RPM_DIR}' and '${TOOLS_RPM_DIR}' now contain all necessary packages."
echo "You can now copy this entire project directory to your offline machine and run the main build script."
