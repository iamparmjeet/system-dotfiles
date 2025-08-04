#!/bin/bash

# A robust script to set up a resilient BTRFS snapshot and
# GRUB update system on Arch Linux.
# It must be run with sudo privileges.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Define packages ---
OFFICIAL_PKGS="timeshift grub-btrfs inotify-tools"
AUR_PKGS="timeshift-autosnap"

# --- Check for an AUR helper ---
if command -v yay &> /dev/null; then
    AUR_HELPER="yay"
elif command -v paru &> /dev/null; then
    AUR_HELPER="paru"
else
    AUR_HELPER=""
fi

echo "--- Step 1: Installing packages... ---"
if [[ -n "$AUR_HELPER" ]]; then
    echo "Found AUR helper '$AUR_HELPER'. Installing all packages with it."
    # Use the AUR helper to install both official and AUR packages
    $AUR_HELPER -S --noconfirm --needed $OFFICIAL_PKGS $AUR_PKGS
else
    echo "No AUR helper found. Installing official packages with pacman."
    # Install official packages only
    pacman -S --noconfirm --needed $OFFICIAL_PKGS
    echo "-----------------------------------------------------------------"
    echo "IMPORTANT: Please install '$AUR_PKGS' from the AUR manually."
    echo "Example: git clone https://aur.archlinux.org/timeshift-autosnap.git"
    echo "         cd timeshift-autosnap && makepkg -si"
    echo "-----------------------------------------------------------------"
    # We exit here because the setup is incomplete without the AUR package.
    exit 1
fi


echo "--- Step 2: Configuring timeshift-autosnap to not update GRUB... ---"
sed -i 's/updateGrub = true/updateGrub = false/' /etc/timeshift-autosnap.conf

echo "--- Step 3: Creating pacman hook for kernel updates... ---"
# FIX: Ensure the hooks directory exists before creating a file in it.
mkdir -p /etc/pacman.d/hooks

tee /etc/pacman.d/hooks/grub.hook > /dev/null <<'EOF'
[Trigger]
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen
Target = linux-hardened

[Action]
Description = Updating GRUB config after kernel upgrade...
When = PostTransaction
Exec = /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "--- Step 4: Configuring and enabling the grub-btrfsd daemon... ---"
# Create a systemd override directory for the service
mkdir -p /etc/systemd/system/grub-btrfsd.service.d

# Create the override file to add the --timeshift-auto flag
tee /etc/systemd/system/grub-btrfsd.service.d/override.conf > /dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto
EOF

# Reload systemd to apply changes, then enable and start the service
systemctl daemon-reload
systemctl enable --now grub-btrfsd

echo ""
echo "✅ Setup Complete!"
echo "Your system is now configured for automated snapshots and robust GRUB updates."
