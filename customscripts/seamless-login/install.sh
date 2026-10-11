#!/usr/bin/env bash
# Install Omarchy seamless login: tty1 service replaces SDDM autologin. Run: sudo bash install.sh
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
cc -O2 -Wall -o /usr/local/bin/seamless-login "$D/seamless-login.c"
install -m 644 "$D/omarchy-seamless-login.service" /etc/systemd/system/omarchy-seamless-login.service
systemd-analyze verify /etc/systemd/system/omarchy-seamless-login.service
systemctl daemon-reload
systemctl disable sddm.service
systemctl enable omarchy-seamless-login.service
echo "Done. Reboot to switch. Rollback (from tty2 with Ctrl+Alt+F2):"
echo "  sudo systemctl disable omarchy-seamless-login.service && sudo systemctl enable sddm.service && sudo reboot"
