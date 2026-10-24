#!/usr/bin/env python3
# smc-watch: print the SMC zone power controller live, to see what t2-cruise reacts to.
# Copyright (C) 2026 flo-coast. GPL v3 or later.
#
#   PZ0F/PZ0E  CPU+GPU filtered power / budget (W)    PZ0T  throttle level 0-100 (PROCHOT at 100)
#   MSLC/MSLG  P-state limit requests for CPU / GPU   MHz   average CPU clock
#
# usage: sudo smc-watch.py [interval_s] [csv_file]
import fcntl, glob, os, struct, sys, time

KEYS = ["PZ0E", "PZ0F", "PZ0T", "PZ1F", "PZ2F", "MSLC", "MSLG"]

def find_smc():
    for d in glob.glob("/sys/bus/acpi/drivers/applesmc/APP0001:*") + glob.glob("/sys/devices/platform/applesmc*"):
        if os.path.exists(f"{d}/key_at_index"):
            return d
    sys.exit("applesmc with the key_at_index interface not found")

def mhz():
    f = [int(open(p).read()) for p in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")]
    return sum(f) // len(f) // 1000 if f else 0

def main():
    if os.geteuid() != 0:
        sys.exit("needs root")
    interval = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    out = open(sys.argv[2], "w", buffering=1) if len(sys.argv) > 2 else None
    smc = find_smc()
    os.makedirs("/run/t2-cruise", exist_ok=True)
    lockf = open("/run/t2-cruise/smc.lock", "a")
    sel = lambda i: open(f"{smc}/key_at_index", "w").write(str(i))
    index = {}
    fcntl.flock(lockf, fcntl.LOCK_EX)
    try:
        for i in range(int(open(f"{smc}/key_count").read())):
            sel(i)
            n = open(f"{smc}/key_at_index_name").read().strip()
            if n in KEYS:
                index[n] = i
    finally:
        fcntl.flock(lockf, fcntl.LOCK_UN)
    keys = [k for k in KEYS if k in index]
    head = "time      " + " ".join(f"{k:>6}" for k in keys) + "    MHz"
    print(head)
    if out:
        out.write("time," + ",".join(keys) + ",mhz\n")
    while True:
        vals = []
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            for k in keys:
                sel(index[k])
                d = open(f"{smc}/key_at_index_data", "rb").read()
                vals.append(struct.unpack("<f", d)[0] if len(d) == 4 else d[0])
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)
        t, m = time.strftime("%H:%M:%S"), mhz()
        print(f"{t}  " + " ".join(f"{v:6.1f}" if isinstance(v, float) else f"{v:6d}" for v in vals) + f" {m:6d}")
        if out:
            out.write(f"{t}," + ",".join(f"{v:.2f}" if isinstance(v, float) else str(v) for v in vals) + f",{m}\n")
        time.sleep(interval)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
