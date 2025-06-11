# Kickstart file for ArttulOS
# Version: 1.7 - Dynamically finds the boot drive.
#
# SECURITY WARNING: Plaintext passwords are used. Change them immediately after installation.
# Default User: ArttulOS
# Default Pass: arttulos

#====================================================
# 1. System Installation & Localization
#====================================================

# Use graphical mode installation
graphical

# Use CD/DVD or network URL for installation source
# Official Rocky Linux repositories
url --url="https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/"
repo --name="AppStream" --baseurl="https://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/"

# Add the ELRepo repository for the mainline kernel
repo --name="elrepo-kernel" --baseurl="https://elrepo.org/linux/kernel/el9/x86_64/"

# System language, keyboard layout, and timezone
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone America/Los_Angeles --isUtc

#====================================================
# 2. Network and Security Configuration
#====================================================

# Network information - Use DHCP on the first ethernet device
network --onboot=yes --device=eth0 --bootproto=dhcp --ipv6=auto --activate
network --hostname=arttulos.localdomain

# Root password - INSECURE! Change this after installation.
rootpw --plaintext arttulos

# Firewall configuration - Enabled by default, allowing SSH traffic
firewall --enabled --service=ssh

# SELinux configuration - Enforcing mode is the default and best practice
selinux --enforcing

#====================================================
# 3. Disk Partitioning
#====================================================

# Clear the Master Boot Record and remove all existing partitions
zerombr
clearpart --all --initlabel

# Use automated LVM partitioning for simplicity and flexibility
autopart --type=lvm

# Bootloader configuration - The installer will automatically find the boot drive.
bootloader --location=mbr

# Reboot the system after installation is complete
reboot

#====================================================
# 4. Package Selection
#====================================================
%packages --instLangs=en_US --excludedocs

@core
@server

# Install the latest mainline kernel from ELRepo
kernel-ml
kernel-ml-devel
kernel-ml-tools

# Base utilities
openssh-server
policycoreutils-python-utils
vim-enhanced
wget
curl
git
kexec-tools

# Applications
firefox
gajim
polari
element-desktop

%end

#====================================================
# 5. Post-Installation Script
#====================================================
%post --log=/root/ks-post.log

echo "Starting ArttulOS post-installation script..."

# --- System Configuration ---
# Set the newly installed ELRepo kernel as the default for the next boot.
# The new kernel will be entry '0' in the grub menu.
echo "Setting default kernel to the new ELRepo kernel..."
grub2-set-default 0

# --- ArttulOS Branding ---
# Set the Message of the Day (MOTD)
cat << EOF > /etc/motd

            (Genesis for the Ascii)

        Welcome to ArttulOS
      This system is running a mainline kernel from ELRepo.

EOF

# Set the pre-login issue message
echo "ArttulOS" > /etc/issue
echo "ArttulOS" > /etc/issue.net


# --- User & SSH Security Hardening ---
# Create a new admin user 'ArttulOS'
echo "Creating admin user 'ArttulOS'..."
useradd ArttulOS -c "ArttulOS Admin"
usermod -aG wheel ArttulOS

# Set a default password for the 'ArttulOS' user.
# !! CRUCIAL: Change this password immediately after first login! !!
echo "ArttulOS:arttulos" | chpasswd

# Configure sudo for the 'wheel' group
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# Harden the SSH daemon configuration
echo "Hardening SSH configuration..."
sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication/PasswordAuthentication/' /etc/ssh/sshd_config

echo "Post-installation script finished."

%end