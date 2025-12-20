sudo tee /etc/systemd/system/omarchy-seamless-login.service <<'EOF'
[Unit]
Description=Omarchy Seamless Auto-Login
After=systemd-user-sessions.service getty@tty1.service systemd-logind.service
Conflicts=getty@tty1.service
PartOf=graphical.target

[Service]
Type=simple
ExecStart=/usr/local/bin/seamless-login uwsm start -- hyprland.desktop
Restart=always
RestartSec=2
User=parm   # change if needed
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal+console
PAMName=login

[Install]
WantedBy=graphical.target
EOF
