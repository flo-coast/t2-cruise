# Unlocking the Radeon power cap (optional)

Without this, t2-cruise can only follow `MSLC` (CPU). That already helps, but the GPU part of the
SMC's request is ignored, so the CPU has to give up more. With the cap unlocked, both follow the SMC
like on macOS.

**Only for the MacBookPro16,1 Radeon Pro 5500M (Navi 14).** Apple's pp_table has every overdrive cap set
to 0, so `power1_cap` is fixed at 50 W. `pptable-powercap.py` sets `ODCAP_POWER_LIMIT` and lets the cap go
down to 10 W (never above the default 50 W, no overclocking).

## Prerequisite, the memory clock fix
On this model the stock pp_table already needs fixing, or the Radeon hangs when it switches memory clocks
(root cause found by jahs, [drm/amd #6005](https://gitlab.freedesktop.org/drm/amd/-/work_items/6005)).
Use jahs' `apple-uclk-pptable.py` from that issue. The power cap patch goes on top of the same table,
in **one** upload.

## Boot script example
Runs at every boot (the table is lost on reboot). `card2` here is the Radeon; check yours with
`ls /sys/bus/pci/devices/0000:03:00.0/drm/` (`card0` can be the Touch Bar).

```sh
#!/bin/sh
G=/sys/bus/pci/devices/0000:03:00.0
T=/run/amdgpu-pptable.bin
echo low > $G/power_dpm_force_performance_level
python3 /path/to/apple-uclk-pptable.py card2 --save $T --quiet &&   # jahs' fix, saved to a file
python3 /path/to/pptable-powercap.py $T &&                          # + power cap unlock
cat $T > $G/pp_table                                                # one upload
echo auto > $G/power_dpm_force_performance_level
cat $G/hwmon/hwmon*/power1_cap_min                                  # should now say 10000000
```

Order the t2-cruise service after this script (`After=` in `t2-cruise.service`) so it sees the
unlocked range. If a boot ever hangs, add `systemd.mask=<your-service>.service` to the kernel command line.
