#!/bin/bash
# load-test.sh: reproduce the brake. idle -> GPU -> GPU+CPU -> cooldown, while smc-watch logs.
# Needs glmark2 and stress-ng. Run once with t2-cruise stopped and once running, compare the logs:
# without it PZ0T climbs to 100 and the CPU drops to 800 MHz; with it PZ0T levels off.
# usage: sudo ./load-test.sh <label> [idle_s gpu_s both_s cool_s]
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo (smc-watch needs root)"; exit 1; }
L=${1:-test}; IDLE=${2:-30}; GPU=${3:-120}; BOTH=${4:-240}; COOL=${5:-60}
DIR=$(dirname "$(readlink -f "$0")")
U=${SUDO_USER:-root}
# the AMD dGPU's PCI address for DRI_PRIME (DRI_PRIME=1 can land on the iGPU on these Macs)
PCI=$(for d in /sys/bus/pci/devices/*; do
        [ "$(cat $d/vendor)" = 0x1002 ] && case $(cat $d/class) in 0x03*) basename $d; break;; esac; done)
[ -n "$PCI" ] || { echo "no AMD GPU found"; exit 1; }
PRIME=pci-$(echo "$PCI" | tr ':.' '__')

python3 -I "$DIR/smc-watch.py" 1 "$L.csv" > /dev/null &
WATCH=$!
trap 'kill $WATCH 2>/dev/null; pkill -f "glmark2 --off-screen"; pkill stress-ng' EXIT
mark() { echo "$(date +%H:%M:%S) $1"; }
mark idle; sleep "$IDLE"
mark gpu
for i in 1 2; do
  sudo -u "$U" env DRI_PRIME=$PRIME glmark2 --off-screen -s 2560x1440 --run-forever -b terrain >/dev/null 2>&1 &
done
sleep "$GPU"
mark both
sudo -u "$U" stress-ng --cpu "$(nproc)" --cpu-method matrixprod --timeout "${BOTH}s" >/dev/null 2>&1 &
sleep "$BOTH"
mark cool; pkill -f "glmark2 --off-screen"
sleep "$COOL"
mark end
echo "log: $L.csv (look at PZ0T and MHz)"
