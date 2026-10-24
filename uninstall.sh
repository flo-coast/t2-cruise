#!/bin/sh
# Removes t2-cruise. Stopping the service restores the CPU and GPU limits.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
systemctl disable --now t2-cruise.service 2>/dev/null || true
rm -f /usr/local/bin/t2-cruised /etc/systemd/system/t2-cruise.service
systemctl daemon-reload
echo "t2-cruise removed (config /etc/t2-cruise.conf kept, delete it if you like)"
