#!/usr/bin/env python3
# Copyright (C) 2026 flo-coast. GPL v3 or later.
"""Unlock lowering the Radeon Pro 5500M power cap (MacBookPro16,1).

Apple's pp_table has every overdrive cap set to 0, so amdgpu reports
power1_cap_min == power1_cap_max == 50 W and the cap cannot be lowered.
navi10_init_ppt_limits() derives the minimum from the table alone:
    min = default * (100 - overdrive_table.min[POWERPERCENTAGE]) / 100
if overdrive_table.cap[ODCAP_POWER_LIMIT] is set (no ppfeaturemask needed).
This patch sets that cap and POWERPERCENTAGE min = 80 (-> 10 W) and keeps the
maximum at the default (max[POWERPERCENTAGE] = 0, no overclocking).

usage: pptable-powercap.py <pptable.bin>   patch the file in place

Only tested on the MacBookPro16,1 Radeon Pro 5500M (Navi 14). The script refuses tables that
don't look exactly like Apple's (size, format and the expected overdrive values).
"""
import struct
import sys

PPT_SIZE = 0x68A                 # sizeof(struct smu_11_0_powerplay_table)
OFF_OD = 0xB6                    # struct smu_11_0_overdrive_table (ends at smc_pptable 0x1E2)
OFF_CAP = OFF_OD + 12            # u8 cap[32]
OFF_MAX = OFF_CAP + 32           # u32 max[32]
OFF_MIN = OFF_MAX + 128          # u32 min[32]
ODCAP_POWER_LIMIT = 3
ODSETTING_POWERPERCENTAGE = 9
LOWER_PERCENT = 80

def main() -> int:
    path = sys.argv[1]
    t = bytearray(open(path, "rb").read())
    if len(t) != PPT_SIZE or t[2] != 12:
        print(f"unexpected table (size {len(t)}, format {t[2]}), not patched", file=sys.stderr)
        return 1
    pct_max = struct.unpack_from("<I", t, OFF_MAX + 4 * ODSETTING_POWERPERCENTAGE)[0]
    pct_min = struct.unpack_from("<I", t, OFF_MIN + 4 * ODSETTING_POWERPERCENTAGE)[0]
    cap = t[OFF_CAP + ODCAP_POWER_LIMIT]
    if (cap, pct_min, pct_max) == (1, LOWER_PERCENT, 0):
        print("already patched")
        return 0
    if (cap, pct_min, pct_max) != (0, 20, 20):
        print(f"unexpected OD values cap={cap} min={pct_min} max={pct_max}, not patched", file=sys.stderr)
        return 1
    t[OFF_CAP + ODCAP_POWER_LIMIT] = 1
    struct.pack_into("<I", t, OFF_MIN + 4 * ODSETTING_POWERPERCENTAGE, LOWER_PERCENT)
    struct.pack_into("<I", t, OFF_MAX + 4 * ODSETTING_POWERPERCENTAGE, 0)
    open(path, "wb").write(t)
    print(f"patched: ODCAP_POWER_LIMIT=1, power range -{LOWER_PERCENT}%/+0%")
    return 0

if __name__ == "__main__":
    sys.exit(main())
