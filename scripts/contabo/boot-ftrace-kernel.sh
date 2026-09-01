#!/usr/bin/env bash
# boot-ftrace-kernel.sh — one-time set GRUB to ftrace kernel and reboot.
set -euo pipefail
ENTRY='gnulinux-advanced-cc6f3ac6-f24d-4276-abe9-c242adec4e04>gnulinux-6.19.0-rc7-g9854922412d3-dirty-advanced-cc6f3ac6-f24d-4276-abe9-c242adec4e04'
sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"${ENTRY}\"|" /etc/default/grub
grep GRUB_DEFAULT /etc/default/grub
update-grub
reboot
