#!/bin/bash
# Collect power/thermal data on macOS for t2-cruise research (MacBookPro16,1).
# Run in Terminal from the folder that holds this script: sudo bash mac-collect.sh
# Result: ~/Desktop/t2-cruise-mac.tar.gz
set -u
[[ $EUID -eq 0 ]] || { echo "run as: sudo bash $0"; exit 1; }
cd "$(dirname "$0")"
U=${SUDO_USER:-$(stat -f %Su .)}
OUT=/tmp/t2-cruise-mac; rm -rf $OUT; mkdir -p $OUT/dumps $OUT/plists
L=mac1; IDLE=30; GPU=120; BOTH=240; COOL=60

echo "== build"
xcode-select -p >/dev/null 2>&1 || { echo "Xcode Command Line Tools missing: run 'xcode-select --install' first"; exit 1; }
clang -O2 -framework IOKit -o smcdump smcdump.c || exit 1
clang -O2 -fobjc-arc -framework Metal -framework Foundation -o gpuburn gpuburn.m || exit 1
cc -O2 -pthread -o cpuburn cpuburn.c || exit 1

echo "== system info"
sw_vers > $OUT/sw_vers.txt
BOARD=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/board-id/ {print $4}')
echo "$BOARD" > $OUT/board-id.txt
pmset -g everything > $OUT/pmset.txt 2>&1
pmset -g therm > $OUT/pmset-therm.txt 2>&1
sysctl -a 2>/dev/null | grep -iE 'xcpm|machdep.cpu|hw\.' > $OUT/sysctl.txt
ioreg -l -w0 > $OUT/ioreg-full.txt
for c in X86PlatformPlugin X86PlatformShim AGPM AppleSMC ACPI_SMC_PlatformPlugin IOPlatformPluginDevice; do
  ioreg -l -w0 -r -c $c > $OUT/ioreg-$c.txt 2>&1
done
kextstat 2>/dev/null > $OUT/kextstat.txt || kmutil showloaded > $OUT/kextstat.txt 2>&1
./smcdump -plimit > $OUT/smc-plimit.txt

echo "== kext plists (thermal/power tables)"
E=/System/Library/Extensions
for k in $(ls -d $E/*.kext $E/*.kext/Contents/PlugIns/*.kext 2>/dev/null | grep -iE 'platform|power|thermal|smc|agpm|agdc|graphicspower|cpupm'); do
  d=$OUT/plists/$(echo ${k#$E/} | tr '/' '_')
  mkdir -p "$d"
  cp "$k/Contents/Info.plist" "$d/" 2>/dev/null
  [ -d "$k/Contents/Resources" ] && find "$k/Contents/Resources" -name '*.plist' -exec cp {} "$d/" \; 2>/dev/null
done
find $OUT/plists -iname "*$BOARD*" > $OUT/board-plists.txt

echo "== load test (about $(( (IDLE+GPU+BOTH+COOL)/60 + 1 )) min, fans will get loud, don't touch the Mac)"
caffeinate -dimsu -t $((IDLE+GPU+BOTH+COOL+60)) &
SAMPLERS=cpu_power,gpu_power,thermal,smc,gpu_agpm_stats
powermetrics -i 1000 --samplers $SAMPLERS -o $OUT/powermetrics.txt >/dev/null 2>&1 &
PM=$!; sleep 2
kill -0 $PM 2>/dev/null || { powermetrics -i 1000 --samplers cpu_power,gpu_power,thermal -o $OUT/powermetrics.txt >/dev/null 2>&1 & PM=$!; }
mark() { echo "$(date +%H:%M:%S) $1" | tee -a $OUT/$L.phases; }
mark idle; ./smcdump -loop $OUT/dumps $L-idle $IDLE
mark gpu;  ./gpuburn $((GPU+BOTH)) > $OUT/gpuburn.txt 2>&1 & GB=$!
./smcdump -loop $OUT/dumps $L-gpu $GPU
mark both; ./cpuburn 16 $BOTH & CB=$!
./smcdump -loop $OUT/dumps $L-both $BOTH
mark cool; kill $GB $CB 2>/dev/null
./smcdump -loop $OUT/dumps $L-cool $COOL
mark end
kill $PM 2>/dev/null; sleep 1

tar -czf /Users/$U/Desktop/t2-cruise-mac.tar.gz -C /tmp t2-cruise-mac && chown $U /Users/$U/Desktop/t2-cruise-mac.tar.gz
echo "== done: ~/Desktop/t2-cruise-mac.tar.gz"
