# ArttulOS Linux Kickstart File # --- System Configuration --- # Language and keyboard settings lang en_US.UTF-8 keyboard us # Network configuration: Use DHCP for network setup network --bootproto=dhcp --activate --hostname=arttulos-host
# Root password (replace 'your_secure_password' with a strong password)
# Use --iscrypted for a hashed password (e.g., generated with `python3 -c 'import crypt; print(crypt.crypt("your_password", crypt.METHOD_SHA512))'`)
# For testing or initial setup, you can use --plaintext, but it's not recommended for production.

repo --name="BaseOS" --baseurl=http://dl.rockylinux.org/pub/rocky/9/BaseOS/$basearch/os/ --cost=200
repo --name="AppStream" --baseurl=http://dl.rockylinux.org/pub/rocky/9/AppStream/$basearch/os/ --cost=200
repo --name="CRB" --baseurl=http://dl.rockylinux.org/pub/rocky/9/CRB/$basearch/os/ --cost=200
repo --name="extras" --baseurl=http://dl.rockylinux.org/pub/rocky/9/extras/$basearch/os --cost=200
repo --name="elrepo-kernel" --baseurl=https://elrepo.org/linux/kernel/el9/$basearch/ --cost=100


#added these from rocky kickstart :P
xconfig --startxonboot

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
part swap --fstype="swap" --size=2048
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
%packages
@^workstation # This group includes GNOME desktop and common desktop applications.
wget
curl
git
vim
tmux
dnf-utils # Useful for managing DNF modules and repositories
@anaconda-tools
@base-x
@core
@gnome-desktop
@guest-desktop-agents
@hardware-support
@internet-browser
#@multimedia not sure on this one
@networkmanager-submodules
@workstation-product
wget
systemd-boot
epel-release
openssh-server
openssh-clients
firefox 
gnome-tweaks 
nautilus-extensions 
dracut-live
flatpak
systemd-boot
efibootmgr
syslinux 
syslinux-extlinux
memtest86+
anaconda
anaconda-install-env-deps
anaconda-live
chkconfig
dracut-live
efi-filesystem
efibootmgr
efivar-libs
glibc-all-langpacks
grub2-common
grub2-efi-*64
grub2-efi-*64-cdboot
grub2-pc-modules
grub2-tools
grub2-tools-efi
grub2-tools-extra
grub2-tools-minimal
grubby
initscripts
#kernel
#kernel-modules
#kernel-modules-extra
livesys-scripts
glib2-devel
kernel-ml
kernel-ml-core
kernel-ml-modules
kernel-ml-headers
-@dial-up
-@input-methods
-@standard
-gfs2-utils
-reiserfs-utils
-shim-unsigned-*64

%end


# fixes from rocky ((copy and paste lmao
%post --nochroot
# only works on x86_64
if [ "unknown" = "i386" -o "unknown" = "x86_64" ]; then
    # For livecd-creator builds. livemedia-creator is fine.
    if [ ! -d /LiveOS ]; then mkdir -p /LiveOS ; fi
    cp /usr/bin/livecd-iso-to-disk /LiveOS
fi

%end

%post

sed -i 's/^livesys_session=.*/livesys_session="gnome"/' /etc/sysconfig/livesys

%end

# --- Post-Installation Script ---
# This section runs commands after the base system is installed.
%post --log=/root/ks-post.log


echo "add rocky shit"
# bug fix from rocky
cat >> /etc/fstab << EOF
vartmp   /var/tmp    tmpfs   defaults   0  0
EOF

#bug fix from rocky
# PackageKit likes to play games. Let's fix that.
rm -f /var/lib/rpm/__db*
releasever=$(rpm -q --qf '%{version}\n' --whatprovides system-release)
basearch=$(uname -i)
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
echo "Packages within this LiveCD"
rpm -qa

# Note that running rpm recreates the rpm db files which aren't needed or wanted
rm -f /var/lib/rpm/__db*

# go ahead and pre-make the man -k cache (#455968)
/usr/bin/mandb

# make sure there aren't core files lying around
rm -f /core*

# remove random seed, the newly installed instance should make it's own
rm -f /var/lib/systemd/random-seed

# convince readahead not to collect
# FIXME: for systemd

echo 'File created by kickstart. See systemd-update-done.service(8).' \
    | tee /etc/.updated >/var/.updated

# Drop the rescue kernel and initramfs, we don't need them on the live media itself.
# See bug 1317709
rm -f /boot/*-rescue*

# Disable network service here, as doing it in the services line
# fails due to RHBZ #1369794 - the error is expected
systemctl disable network

# Remove machine-id on generated images
rm -f /etc/machine-id
touch /etc/machine-id

# relabel
#/usr/sbin/restorecon -RF /
/usr/sbin/fixfiles -R -a restore

#



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

#enable flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

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

# configure gnome, do later get installer going

# configure systemd boot
bootctl --esp-path=/boot/efi install

#dnf -y remove grub2-efi-x64 grub2-efi-x64-cdboot grubby grub2-common shim-*

mkdir -p /boot/efi/loader/entries

ROOT_UUID=$(findmnt -n -o UUID --target /)
KERNEL_VER=$(ls /boot/vmlinuz-* | sed 's/.*vmlinuz-//' | head -n 1)

cat <<EOF > /boot/efi/loader/entries/arttulos.conf
title   ArttulOS Linux 9
linux   /vmlinuz-${KERNEL_VER}
initrd  /initramfs-${KERNEL_VER}.img
options root=UUID=${ROOT_UUID} rhgb quiet
EOF

cat <<EOF > /boot/efi/loader/loader.conf
default arttulos.conf
timeout 3
editor  no
EOF

# do it again for extra measures :P
bootctl --esp-path=/boot/efi install
# end of soystemd boot

# Hostname reinforcement
hostnamectl set-hostname arttulos


# 3. Enable Newer Packages / Repositories and System Update
# ----------------------------------------------------------
echo "Enabling EPEL and performing system update..."

# EPEL (Extra Packages for Enterprise Linux) is already installed via %packages,
# but we ensure it's enabled and updated.
dnf -y install epel-release
dnf config-manager --set-enabled epel

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

systemctl enable livesys.service
systemctl enable livesys-late.service
# Enable tmpfs for /tmp - this is a good idea
systemctl enable tmp.mount

# copy this anaconda config into the iso for the installer later


echo "--- ArttulOS Post-Installation Script Complete ---"

%end
