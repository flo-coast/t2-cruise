#!/bin/sh
# Installs t2-cruise: daemon, systemd service, config (an existing config is kept).
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
case $model in
  MacBookPro16,1) ;;
  *) echo "Note: $model is untested. t2-cruise checks for the needed SMC keys at start and"
     echo "refuses to run without them. Please report how it goes." ;;
esac

install -Dm755 t2-cruised /usr/local/bin/t2-cruised
install -Dm644 t2-cruise.service /etc/systemd/system/t2-cruise.service
[ -e /etc/t2-cruise.conf ] || install -Dm644 t2-cruise.conf /etc/t2-cruise.conf

echo "Checking that the SMC sends limit requests (dry run, 3 s)..."
rc=0
timeout 3 python3 -I /usr/local/bin/t2-cruised --dry-run || rc=$?
# 124 = still running after 3 s, which is what we want
[ $rc = 0 ] || [ $rc = 124 ] || { echo "dry run failed, not enabling the service"; exit 1; }
systemctl daemon-reload
systemctl enable t2-cruise.service
systemctl restart t2-cruise.service   # an update must replace the running daemon
echo
echo "t2-cruise installed and running. Watch it work: journalctl -fu t2-cruise"
