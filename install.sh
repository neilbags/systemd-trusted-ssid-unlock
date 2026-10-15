#!/bin/bash
# Install systemd-trusted-ssid-unlock. Run from this directory as root (or it re-runs with sudo).
set -e
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
cd "$(dirname "$0")"

if [[ $1 == --uninstall ]]; then
	systemctl disable systemd-trusted-ssid-unlock.service 2>/dev/null || true
	rm -f /usr/local/bin/systemd-trusted-ssid-unlock /usr/local/bin/systemd-trusted-ssid-unlock-add \
		/usr/lib/systemd/system-sleep/systemd-trusted-ssid-unlock \
		/etc/systemd/system/systemd-trusted-ssid-unlock.service \
		/etc/NetworkManager/dispatcher.d/90-systemd-trusted-ssid-unlock
	systemctl daemon-reload
	echo "Uninstalled. Trusted APs are left in /etc/systemd-trusted-ssid-unlock; remove it if you like."
	exit 0
fi

for cmd in iw nmcli ip logger flock; do
	command -v "$cmd" > /dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done

install -m755 systemd-trusted-ssid-unlock systemd-trusted-ssid-unlock-add /usr/local/bin/
install -Dm755 systemd/systemd-trusted-ssid-unlock.sleep-hook /usr/lib/systemd/system-sleep/systemd-trusted-ssid-unlock
install -m644 systemd/systemd-trusted-ssid-unlock.service /etc/systemd/system/
install -m755 NetworkManager/90-systemd-trusted-ssid-unlock /etc/NetworkManager/dispatcher.d/
install -dm755 /etc/systemd-trusted-ssid-unlock
[[ -e /etc/systemd-trusted-ssid-unlock/config ]] || install -m644 config.example /etc/systemd-trusted-ssid-unlock/config
systemctl daemon-reload
systemctl enable systemd-trusted-ssid-unlock.service

echo "Installed. Connect to a network you trust and run: systemd-trusted-ssid-unlock-add"
