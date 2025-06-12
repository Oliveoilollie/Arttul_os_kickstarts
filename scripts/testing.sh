#!/bin/bash
# ==============================================================================
# Diagnostic Script: Inspect .treeinfo (File Output Version)
#
# Description:
# This script safely mounts a given ISO file and saves the exact content
# of the .treeinfo file to 'treeinfo_output.txt' for analysis.
# ==============================================================================

set -e

# --- Configuration ---
readonly DIAG_DIR="treeinfo_diagnostics"
readonly OUTPUT_FILE="treeinfo_output.txt"

# --- Helper Functions ---
print_msg() {
    local color=$1
    local message=$2
    local nocolor='\033[0m'
    case "$color" in
        "blue")   echo -e "\n\033[1;34m[INFO]\033[0m ${message}${nocolor}" ;;
        "red")    echo -e "\n\033[1;31m[ERROR]\033[0m ${message}${nocolor}" >&2 ;;
    esac
}

cleanup() {
    if [ -d "${DIAG_DIR}" ]; then
        print_msg "blue" "Performing cleanup..."
        umount "${DIAG_DIR}/iso_mount" &>/dev/null || true
        rm -rf "${DIAG_DIR}"
    fi
}

# --- Main Execution ---
main() {
    trap cleanup EXIT SIGHUP SIGINT SIGTERM

    print_msg "blue" "Verifying prerequisites..."
    if [[ "$EUID" -ne 0 ]]; then
        print_msg "red" "This diagnostic script must be run as root. Please use sudo."
        exit 1
    fi

    # Prepare a clean directory
    rm -rf "${DIAG_DIR}"
    mkdir -p "${DIAG_DIR}/iso_mount"

    local base_iso_path
    read -p "Please enter the full path to the official Rocky Linux 9 DVD ISO: " base_iso_path
    if [ ! -f "$base_iso_path" ]; then
        print_msg "red" "Source ISO file not found at '${base_iso_path}'."
        exit 1
    fi

    print_msg "blue" "Mounting ISO to inspect .treeinfo..."
    mount -o loop,ro "$base_iso_path" "${DIAG_DIR}/iso_mount"

    local treeinfo_path="${DIAG_DIR}/iso_mount/.treeinfo"

    if [ ! -f "$treeinfo_path" ]; then
        print_msg "red" "Could not find a .treeinfo file at the root of the provided ISO."
        exit 1
    fi

    # Redirect all output from this block to the output file
    (
        echo "==================== Contents of .treeinfo from ${base_iso_path} ===================="
        echo "Generated on: $(date)"
        echo "======================================================================================="
        echo ""
        cat "${treeinfo_path}"
    ) > "${OUTPUT_FILE}"

    # Return ownership of the created file to the user who ran sudo
    if [ -n "$SUDO_USER" ]; then
        chown "${SUDO_USER}:${SUDO_GROUP:-$SUDO_USER}" "${OUTPUT_FILE}"
    fi

    print_msg "blue" "Diagnostics complete. A file named '${OUTPUT_FILE}' has been created in this directory."
    print_msg "blue" "Please provide the contents of this file for analysis."
}

# Run the main function
main "$@"
