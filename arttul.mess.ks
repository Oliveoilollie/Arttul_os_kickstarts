# ArttulOS Linux Kickstart File # --- System Configuration --- # Language and keyboard settings lang en_US.UTF-8 keyboard us # Network configuration: Use DHCP for network setup network --bootproto=dhcp --activate --hostname=arttulos-host
# Root password (replace 'your_secure_password' with a strong password)
# Use --iscrypted for a hashed password (e.g., generated with `python3 -c 'import crypt; print(crypt.crypt("your_password", crypt.METHOD_SHA512))'`)
# For testing or initial setup, you can use --plaintext, but it's not recommended for production.

# simple and easy password :P
rootpw --plaintext arttul

# Firewall configuration: Enable firewall with default rules, explicitly allowing SSH
firewall --enabled --ssh

# WHY DIDNT THEY DO THIS
network --bootproto=dhcp --device=link --activate --hostname=arttulos

# SELinux configuration: Set to enforcing mode, this is default. why is this here?
selinux --enforcing

# Timezone setting
timezone America/Los_Angeles --utc

# Bootloader configuration: Install GRUB2 on the first disk (sda), grub dead. dont use this
#bootloader --location=mbr --boot-drive=sda
#bootloader --timeout=5 --append="rhgb quiet"

# thanks AI, this is minimal for grub till we nuke it and use systemd boot XD
bootloader --timeout=5 --append="rhgb quiet"

# Clear the Master Boot Record (MBR)
zerombr

# Clear existing partitions and create new ones, we are using gpt. so anaconda will be like YOOOO use systemd boot, update. anaconda didnt like that
clearpart --all --initlabel
#clearpart --all --initlabel --drives=sda

# Partitioning scheme:
# /boot partition (600MB)
# swap partition (2GB - adjust based on RAM)
# / (root) partition (remaining space)
part /boot --fstype="xfs" --size=600
#part /boot --fstype="efi" --size=600 --label=BOOT --fsoptions="umask=0077,shortname=winnt"
part swap --fstype="swap" --size=2048
#part / --fstype="xfs" --grow --size=1
part / --fstype="xfs" --size=7096

# System authorization: Enable shadow passwords
auth --useshadow --passalgo=sha512

# Reboot the system after installation
reboot

# URL for installation source (e.g., Rocky Linux 9 AppStream/BaseOS)
# Replace with the actual URL of your Rocky Linux mirror or local repository
# Using a more generic mirror URL if available, or keep the specific one.
url --url="http://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/"

# --- Package Selection ---
# Define the environment group for installation.
# For an average consumer with GNOME, @^workstation is the most suitable.
%packages
@^workstation # This group includes GNOME desktop and common desktop applications.

# Essential utilities and tools (some might be included in workstation, but good to ensure)
wget
curl
git
vim
tmux
dnf-utils # Useful for managing DNF modules and repositories

# Ensure OpenSSH server is installed for remote connections
openssh-server
openssh-clients

# For newer packages, we'll enable EPEL later in %post, no this doesnt work 
#epel-release

# Additional common desktop applications for an average consumer, some was commented out bc well not in repo :P
firefox # Web browser
#libreoffice-calc # Spreadsheet
#libreoffice-writer # Word processor
gimp # Image editor
#vlc # Media player
gnome-tweaks # GNOME customization tool
#gnome-shell-extensions # GNOME Shell extensions
#system-config-printer # Printer configuration utility
nautilus-extensions # File manager extensions
# Add any other specific applications you deem necessary for your target audience
dracut-live

#soystemd-boot stuff
systemd-boot
efibootmgr

#because for some fucking reason rocky needs syslinux for bios systems
syslinux 
syslinux-extlinux

# again why
memtest86+

%end

# --- Post-Installation Script ---
# This section runs commands after the base system is installed.
%post --log=/root/ks-post.log

echo "removing grub garbage"
dnf -y remove grub2* shim-* grubby
echo "--- Starting ArttulOS Post-Installation Script ---"

# 1. Rebranding: Modify OS identification files
# --------------------------------------------------
echo "Applying ArttulOS rebranding..."

# Backup original os-release
cp /etc/os-release /etc/os-release.bak

# Create new /etc/os-release for ArttulOS
cat <<EOF > /etc/os-release
NAME="ArttulOS Linux"
PRETTY_NAME="ArttulOS 9"
ID="arttulos"
VERSION_ID="9"
VERSION="9 (ArttulOS)"
ID_LIKE="rocky fedora centos rhel"
PLATFORM_ID="platform:el9"
ANSI_COLOR="0;33"
CPE_NAME="cpe:/o:arttulos:arttulos:9"
HOME_URL="https://www.arttulos.com/"
BUG_REPORT_URL="https://bugs.arttulos.com/"
ROCKY_SUPPORT_PRODUCT="ArttulOS Linux"
ROCKY_SUPPORT_PRODUCT_VERSION="9"
EOF

# Create a custom release file
echo "ArttulOS Linux release 9 (ArttulOS)" > /etc/arttulos-release

# Update /etc/redhat-release to reflect ArttulOS
echo "ArttulOS Linux release 9 (ArttulOS)" > /etc/redhat-release

# Modify /etc/issue and /etc/issue.net (login banners)
echo "ArttulOS Linux 9 \n \l" > /etc/issue
echo "ArttulOS Linux 9" > /etc/issue.net

# Update Message of the Day (MOTD)
cat <<EOF > /etc/motd
Welcome to ArttulOS Linux!
Your friendly and stable desktop experience.
EOF

# 2. GRUB Bootloader Rebranding
# --------------------------------------------------
#echo "Updating GRUB bootloader branding..."
# Change the GRUB distributor name
#sed -i 's/^GRUB_DISTRIBUTOR=".*"/GRUB_DISTRIBUTOR="ArttulOS Linux"/' /etc/default/grub
# Rebuild GRUB configuration
#grub2-mkconfig -o /boot/grub2/grub.cfg

echo "grub is deprecated, now using systemd-boot for better stablity"

mkdir -p /boot/loader/entries
kernelver=$(ls /boot/vmlinuz-* | sed 's/.*vmlinuz-//')
cat <<EOF > /boot/loader/entries/arttulos.conf
title   ArttulOS Linux
linux   /vmlinuz-$kernelver
initrd  /initramfs-$kernelver.img
options root=UUID=$(blkid -s UUID -o value /dev/mapper/$(ls /dev/mapper | grep root)) quiet splash
EOF

cat <<EOF > /boot/loader/loader.conf
default arttulos.conf
timeout 3
editor no
EOF

# Hostname reinforcement
hostnamectl set-hostname arttulos

# 2. soystemd configuration

# 3. Enable Newer Packages / Repositories and System Update
# ----------------------------------------------------------
echo "Enabling EPEL and performing system update..."

# EPEL (Extra Packages for Enterprise Linux) is already installed via %packages,
# but we ensure it's enabled and updated.
#dnf -y install epel-release
#dnf config-manager --set-enabled epel

# Example: Enable a specific DNF module stream for newer software
# Uncomment and modify if you need a specific version of a package from AppStream
# dnf module enable -y nodejs:20 # Example: Enable Node.js 20
# dnf module enable -y postgresql:15 # Example: Enable PostgreSQL 15

# Perform a full system update to get the latest package versions
echo "Running dnf update..."
dnf -y update

# Clean up DNF cache
echo "Cleaning DNF cache..."
dnf clean all

# 4. Configure SSH for remote access
# --------------------------------------------------
echo "Configuring SSH for remote access..."

# Ensure openssh-server is installed (added to %packages as well for robustness)
dnf -y install openssh-server

# Enable and start the SSH service
systemctl enable sshd --now

# Add SSH to the firewall if it wasn't already (redundant with --ssh in firewall, but good for clarity)
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

echo "--- ArttulOS Post-Installation Script Complete ---"

%end
