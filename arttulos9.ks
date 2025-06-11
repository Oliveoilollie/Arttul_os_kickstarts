# Kickstart file for ArttulOS 9 (based on Rocky Linux 9)
# Version: 1.2 - Added ELRepo and mainline kernel installation

#====================================================
# 1. System Installation & Localization
#====================================================

# Use text mode installation
text

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
network --hostname=arttulos9.localdomain

# Root password - THIS IS A PLACEHOLDER!
# Generate your own strong, encrypted password with:
# openssl passwd -6 'your-strong-password'
# Then replace the entire line below.
rootpw --iscrypted $6$SbsO0Ll9y.AWrooe$PEcHjlZjJdzwVFDzW0Vk.B1XbhHVR3qTNpREhhM/PjjlJnE1b2zBb/C0gM0uvDnr6VV4YNlEj6SW8x7yIktt90

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

# Bootloader configuration
bootloader --location=mbr --boot-drive=sda

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

echo "Starting ArttulOS 9 post-installation script..."

# --- System Configuration ---
# Set the newly installed ELRepo kernel as the default for the next boot.
# The new kernel will be entry '0' in the grub menu.
echo "Setting default kernel to the new ELRepo kernel..."
grub2-set-default 0

# --- ArttulOS 9 Branding ---
# Set the Message of the Day (MOTD)
cat << EOF > /etc/motd

            (Genesis for the Ascii)

        Welcome to ArttulOS 9 (Rocky Linux 9 Base)
      This system is running a mainline kernel from ELRepo.

EOF

# Set the pre-login issue message
echo "ArttulOS 9" > /etc/issue
echo "ArttulOS 9" > /etc/issue.net


# --- User & SSH Security Hardening ---
# Create a new admin user 'arttu'
echo "Creating admin user 'arttu'..."
useradd arttu -c "Arttu Admin"
usermod -aG wheel arttu

# Set a placeholder password for the 'arttu' user.
echo "arttu:YourPasswordHere" | chpasswd

# Configure sudo for the 'wheel' group
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# Set up SSH key-based authentication for the 'arttu' user
# !! CRUCIAL: Replace the public key below with YOUR OWN public key !!
echo "Setting up SSH key for 'arttu' user..."
mkdir -p /home/arttu/.ssh
cat << EOF > /home/arttu/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...your...actual...public...key...goes...here user@machine
EOF

# Set correct permissions
chmod 700 /home/arttu/.ssh
chmod 600 /home/arttu/.ssh/authorized_keys
chown -R arttu:arttu /home/arttu/.ssh

# Harden the SSH daemon configuration
echo "Hardening SSH configuration..."
sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication/PasswordAuthentication/' /etc/ssh/sshd_config

echo "Post-installation script finished."

%end