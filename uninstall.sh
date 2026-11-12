#!/bin/bash
# Remove exactly what install.sh installed. Run as root: sudo ./uninstall.sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo $0)." >&2; exit 1; }
for f in /usr/local/sbin/omen-ec-backlight /usr/local/sbin/omen-ec-backlight-detect \
         /etc/udev/rules.d/70-omen-ec-backlight.rules /usr/lib/systemd/system-sleep/omen-ec-backlight /usr/lib/systemd/system-sleep/omen-ec-suspend \
         /etc/omen-ec-backlight.conf /run/omen-ec-backlight.warned; do
  if [ -e "$f" ]; then rm -v -- "$f"; else echo "not present: $f"; fi
done
udevadm control --reload
echo "Done. The EC keeps its last brightness value until reboot. Remove the kernel parameters yourself if you added them."
