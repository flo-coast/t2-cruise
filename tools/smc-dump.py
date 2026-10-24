#!/usr/bin/env python3
# smc-dump: dump all Apple SMC keys on Linux (read-only) as TSV.
# Copyright (C) 2026 flo-coast. GPL v3 or later.
#
# By default only numeric keys (temperatures, power, limits, ...) are printed. Text and blob keys
# (ch8*, hex_, {...) are redacted because some of them hold serial numbers and device IDs.
# Use --raw for everything, and don't post raw dumps publicly.
#
# usage: sudo smc-dump.py [--raw] [keys...] > dump.tsv
import fcntl, glob, os, struct, sys

NUMERIC = ("flt", "ui8", "ui16", "ui32", "si8", "si16", "si32", "sp78", "fpe2", "fp88", "flag")

def find_smc():
    for d in glob.glob("/sys/bus/acpi/drivers/applesmc/APP0001:*") + glob.glob("/sys/devices/platform/applesmc*"):
        if os.path.exists(f"{d}/key_at_index"):
            return d
    sys.exit("applesmc with the key_at_index interface not found")

def decode(typ, d):
    try:
        if typ == "flt" and len(d) == 4: return f"{struct.unpack('<f', d)[0]:.4g}"
        if typ in ("ui8", "flag"): return str(d[0])
        if typ == "si8": return str(struct.unpack("b", d[:1])[0])
        if typ in ("ui16", "ui32"):    # byte order differs between keys: big/little
            return f"{int.from_bytes(d, 'big')}/{int.from_bytes(d, 'little')}"
        if typ == "si16": return str(struct.unpack(">h", d)[0])
        if typ == "sp78": return f"{struct.unpack('>h', d)[0] / 256:.3g}"
        if typ == "fpe2": return f"{int.from_bytes(d, 'big') / 4:.4g}"
        if typ == "fp88": return f"{int.from_bytes(d, 'big') / 256:.4g}"
    except (struct.error, IndexError):
        pass
    return ""

def main():
    raw = "--raw" in sys.argv
    only = {a for a in sys.argv[1:] if not a.startswith("--")}
    if os.geteuid() != 0:
        sys.exit("needs root")
    if raw:
        print("WARNING: --raw output can contain serial numbers, don't post it publicly", file=sys.stderr)
    smc = find_smc()
    os.makedirs("/run/t2-cruise", exist_ok=True)
    lockf = open("/run/t2-cruise/smc.lock", "a")   # shared with t2-cruised
    print("key\ttype\tlen\thex\tdecoded")
    for i in range(int(open(f"{smc}/key_count").read())):
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            with open(f"{smc}/key_at_index", "w") as f:
                f.write(str(i))
            name = open(f"{smc}/key_at_index_name").read().strip()
            typ = open(f"{smc}/key_at_index_type").read().strip()
            if only and name not in only:
                continue
            try:
                data = open(f"{smc}/key_at_index_data", "rb").read()
            except OSError:
                data = None
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)
        if data is None:
            print(f"{name}\t{typ}\t-1\tERR\t")
        elif raw or typ in NUMERIC:
            print(f"{name}\t{typ}\t{len(data)}\t{data.hex()}\t{decode(typ, data)}")
        else:
            print(f"{name}\t{typ}\t{len(data)}\t<redacted>\t")

if __name__ == "__main__":
    main()
