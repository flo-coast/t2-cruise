# t2-cruise

**Cruise control for T2 MacBooks on Linux. No 800 MHz brakes under load.**

> **See also [t2-zone-power](https://github.com/kaiT2en/KaiT2en-Fedora/tree/main/apps/t2-zone-power)** by
> KaiT2en, which found the same mechanism independently and earlier (October 2026) and implements it more
> completely. It reads the SMC's power limit record through the KaiT2en `t2smc` driver, reports the GPU step
> counts and the CPU P-state range back to the SMC like macOS does, and also limits the iGPU and forced idle.
> t2-cruise is the small read-only variant that needs no extra kernel module.

## The problem
On a MacBookPro16,1 running Linux, a combined CPU and GPU load (a game, for example) makes the CPU drop to
**800 MHz** after a few minutes. This happens again and again for several seconds at a time and shows up as
stutters, freezes and frame drops. The temperatures are normal when it happens.

## Why it happens
The Apple SMC manages one power budget for CPU and GPU together, because both share one heat pipe. When the
two draw more than the budget, the SMC sends **P-state limit steps** for the CPU and the GPU. macOS applies
these steps, so the power drops a little and settles just under the budget.

The steps live in the SMC's power limit record, which macOS reads. The SMC also mirrors them in the debug
keys `MSLC` (CPU) and `MSLG` (GPU), which can be read through the standard `applesmc` driver. t2-cruise uses
these keys.

Linux doesn't apply these steps. The power stays above the budget, the SMC's throttle level climbs to 100,
and the SMC then asserts PROCHOT. PROCHOT forces the CPU to its lowest clock of 800 MHz.

## The fix
`t2-cruised` reads `MSLC` and `MSLG` twice a second and applies them the same way macOS does.
- `MSLC` lowers the CPU ceiling by 100 MHz per step (via `intel_pstate`)
- `MSLG` lowers the Radeon power cap by 2.5 W per step (optional, see [gpu/](gpu/))

With the steps applied, the SMC's own control loop settles below the brake, like on macOS.
Details and measurements are in [docs/FINDINGS.md](docs/FINDINGS.md).

t2-cruise only reads the SMC and never writes to it. The only settings it changes are the CPU ceiling and the
GPU power cap, and it restores both when it stops.

## Results (MacBookPro16,1)
| | stock Linux | with t2-cruise |
|---|---|---|
| synthetic load (GPU + all CPU threads, 4 min) | PROCHOT, CPU at 800 MHz | 0 PROCHOT, CPU ≥ 1.7 GHz |
| Guild Wars 2, 4K, 26 min of big fights | regular freezes | 0 PROCHOT, ~30-35 FPS in big fights |

The FPS in heavy scenes are the hardware limit. After about 20 minutes under load the SMC lowers its
long-term budget to ~63-68 W for CPU and GPU together, on macOS as well. t2-cruise removes the brake,
not the budget.

## Requirements
- A T2 MacBook running Linux with the [t2linux](https://t2linux.org) kernel patches.
  Tested on the **MacBookPro16,1** (16", 2019, i9-9880H, Radeon Pro 5500M). Other models are untested, see below.
- `applesmc` loaded (the t2linux kernel has it), `intel_pstate` active, Python 3
- Optional, an unlocked Radeon power cap ([gpu/](gpu/)). Without it only the CPU follows the SMC.

## Install
```sh
git clone https://github.com/flo-coast/t2-cruise
cd t2-cruise
sudo ./install.sh
journalctl -fu t2-cruise        # watch it work
```
The installer first does a dry run and only enables the service if the SMC has the needed keys.

Under load the log shows lines like this one.
```
[apple] MSLC 30 MSLG  7 -> CPU 38% GPU 32.5 W | PZ0T  45.2 PZ0F  71.8/72.4 W
```
`PZ0F/PZ0E` is the CPU and GPU power against the SMC's budget, `PZ0T` is the SMC's throttle level.
`PZ0T` should level off well below 100.

To remove it, run `sudo ./uninstall.sh`. This also restores the limits.

## Policies
The policy is set in `/etc/t2-cruise.conf` and can be switched at runtime with
`echo adaptive | sudo tee /run/t2-cruise/policy`.
- **`apple`** (default) caps the CPU with `MSLC` and the GPU with `MSLG`. This is what macOS does, and it
  felt best in games.
- **`adaptive`** (experimental) splits `MSLC` between CPU and GPU by GPU load. It gives the same FPS in games,
  but the GPU runs near 100 % and queues frames, which makes input feel laggier. Ideas are welcome.

## Tools
| | |
|---|---|
| `tools/smc-watch.py` | live view of the SMC controller (`PZ0E/F/T`, `MSLC/MSLG`, CPU MHz), optional CSV |
| `tools/smc-dump.py` | dumps all SMC keys, by default only numeric keys (text and blob keys can hold serial numbers) |
| `tools/load-test.sh` | reproduces the brake with idle, GPU, GPU+CPU and cooldown phases, logged with smc-watch |
| `macos/` | the read-only kit used to measure macOS under the same load |

## Other T2 models
Other models are untested so far. t2-cruise refuses to start if the SMC doesn't have `MSLC` and `MSLG`.
If yours has them, please open an issue with your model, the output of
`sudo tools/smc-dump.py MSLC MSLG PZ0E PZ0F PZ0T` under load, and how it behaves. Other GPUs (Vega, Polaris,
5600M) may need different step sizes, which can be set in `/etc/t2-cruise.conf`.

## Credits
Reverse-engineered and written by **flo-coast** (2026), with Claude (Anthropic) as a coding assistant.
Thanks to the [t2linux](https://t2linux.org) community, to KaiT2en and Byte for t2-zone-power and for
pointing out that `MSLC`/`MSLG` are debug mirrors, and to jahs for finding the Radeon memory clock bug
([drm/amd #6005](https://gitlab.freedesktop.org/drm/amd/-/work_items/6005)) that made the Radeon usable in
the first place.

If you build on this, please credit this repository.

## License
[GPL v3 or later](LICENSE). There is no warranty. t2-cruise changes CPU and GPU limits on your machine.
It runs daily on the author's MacBookPro16,1, but you use it at your own risk.
