# Findings on the Apple SMC zone power controller (MacBookPro16,1)

Reverse-engineered in October 2026 by flo-coast, by logging the SMC on Linux and on macOS
under the same load. KaiT2en found the same mechanism independently and earlier and built
[t2-zone-power](https://github.com/kaiT2en/KaiT2en-Fedora/tree/main/apps/t2-zone-power) on it, which goes
further (see the end of this document). The machine is a MacBookPro16,1 (i9-9880H, Radeon Pro 5500M, board
Mac-E1008331FDC96864) with macOS 26.6 and Arch Linux with the t2linux kernel.

## The symptom
On Linux, a combined CPU and GPU load (games, or `glmark2` together with `stress-ng`) makes the CPU fall to
**800 MHz** after a few minutes, for several seconds at a time. Temperatures are normal and the power is well
below the RAPL limits. MSR `0x64F` (core perf limit reasons) shows **PROCHOT**, which means the signal comes
from outside the CPU, in this case from the SMC. On macOS the same load never causes this.

## The mechanism
The SMC runs a power controller per **zone**. The keys are all `flt` (little endian) and can be read through
applesmc's `key_at_index` interface.

| key | meaning |
|---|---|
| `PZ0E` / `PZ0F` / `PZ0G` / `PZ0T` | zone 0 = **CPU + GPU** (shared heat pipe), budget W / filtered power W / instant power W / throttle level 0-100 |
| `PZ1*` | zone 1 = CPU (budget 82 W) |
| `PZ2*` | zone 2 = GPU (budget 70 W) |
| `PZ3*`-`PZ5*` | further zones, stayed at 0 in all tests |
| `ZPEN` | zone enable mask (`0x3f`) |

1. `PZ0E` starts at **82 W** and sinks under sustained load, even with the fans at maximum and stable
   temperatures. It is ~73 W after a few minutes and **~63.5 W after ~20 minutes**, which points to a
   long-term heat model of the chassis.
2. While `PZ0F` is above `PZ0E`, the throttle level `PZ0T` integrates up.
3. The SMC turns `PZ0T` into **P-state limit requests**, `MSLC` for the CPU and `MSLG` for the GPU (plain `ui8`).
   `MSLC` is about 0.55 × `PZ0T` and ramps up by about one step every 2 s.
4. **macOS obeys these requests** (X86PlatformPlugin "PLimit", `powermetrics` shows the same numbers as
   "CPU Plimit" and "GPU Plimit"). The power drops until `PZ0F` is about `PZ0E`, and `PZ0T` settles
   around **53**.
5. **Linux ignores them.** `PZ0T` keeps integrating up to **100**, and the SMC also shrinks `PZ2E` (the GPU
   budget, 70 → ~6 W, also ignored). At 100 the SMC asserts **PROCHOT** and the CPU drops to 800 MHz.

The SMC sends exactly the same requests on Linux as on macOS. Linux just never applied them.

## macOS under load (steady state, GPU + 16 CPU threads)
| | value |
|---|---|
| `PZ0T` | rises when `PZ0F > PZ0E`, peaks at 61, settles at **~53** |
| `PZ0F` ≈ `PZ0E` | ~72 W |
| CPU / GPU power | ~33 W / ~39 W |
| `MSLC` / `MSLG` | 30-32 / 7-8 |
| PROCHOT | **0** for the whole run (`powermetrics`) |

Other keys follow the controller as well. `MSAc` / `MSAg` / `MSAi` (`fp88`) look like smoothed CPU / dGPU /
iGPU limits, `MSt0` and `MT0z` are copies of `PZ0T`, `MT0c` / `MT0g` / `MT0t` are the zone 0 CPU and GPU
contributions and an active flag, and the `Q*` family is not decoded yet. `PZ2E` dips on macOS too
(70 → 41 W), but only briefly, until the limits take effect.

The X86PlatformPlugin and AGPM plists contain **no** controller data (no zones, budgets or PID values),
so the controller lives in the SMC firmware. In ioreg the consumers show up as PLimit handlers,
`CPUPLimitDict` (pMin 40), `EGPUPLimitDict` (pMin 15, the Radeon) and `IGPUPLimitDict` (pMin 17).
AGPM runs no power heuristic for the Radeon (`Heuristic ID = -1`), so its limit comes only through PLimit.

## Rebuilding it on Linux
`t2-cruised` polls `MSLC` and `MSLG` every 0.5 s and applies them.
- `MSLC` lowers the CPU ceiling by 100 MHz per step (`intel_pstate/max_perf_pct`)
- `MSLG` lowers the Radeon power cap by 2.5 W per step (`power1_cap`, needs the unlocked cap, see `gpu/`)

Once the power follows the requests, the SMC's own loop stops `PZ0T` from climbing further.

| test (glmark2 ×2 + stress-ng, 4 min) | Linux, stock | Linux + t2-cruise |
|---|---|---|
| `PZ0T` | climbs to 100 | settles at ~34 |
| PROCHOT samples | many | **0** |
| lowest CPU clock | 800 MHz | ~1.7 GHz |

In real use (Guild Wars 2 at 4K over a dock, a 26-minute session with large fights) there was **0 PROCHOT**,
where before the CPU regularly froze at 800 MHz. With the budget at its long-term low of ~63-68 W, large fights
run at ~30-35 FPS. That is the hardware limit and not a brake.

## Lessons from experimenting
- **The GPU should stay below 100 % load.** A "GPU first" policy (throttle the GPU before the CPU) left the
  Radeon at ~500 MHz and 99 % busy. A GPU at 99 % queues frames, so the FPS stayed the same but input and the
  mouse pointer became noticeably laggier. The adaptive policy (split by GPU load) had the same problem.
  The macOS split ("apple") felt direct.
- **The Radeon power cap is locked at 50 W** on this model, because Apple's pp_table sets every overdrive
  cap to 0. Setting `ODCAP_POWER_LIMIT` and a lower `POWERPERCENTAGE` minimum in the table unlocks 10-50 W
  without `amdgpu.ppfeaturemask` (`gpu/pptable-powercap.py`).
- Reading the SMC by index is shared state (`key_at_index` + `key_at_index_data`). Tools that read the SMC
  at the same time have to lock (`/run/t2-cruise/smc.lock`), otherwise they read each other's keys.

## What t2-zone-power adds
Byte from the KaiT2en project pointed out that `MSLC` and `MSLG` are debug mirrors. The actual interface is
the SMC's power limit record (the `cmd 11` record that `macos/smcdump.c -plimit` reads, which was only sampled
at idle here). t2-zone-power reads it through the KaiT2en `t2smc` driver and, like macOS, also writes back to
the SMC.
- `HE0N` / `HI0N` tell the SMC how many limit steps the dGPU and iGPU have (AGPM does this on macOS). Without
  the dGPU count the SMC balances the heat pipe through the CPU alone.
- `MSTS` / `MSPC` report the CPU P-state range (X86PlatformPlugin does this on macOS).
- forced idle through `intel_powerclamp` and an iGPU limit as further actuators

According to Byte this lowers the maximum temperature by about 10 °C. t2-cruise doesn't do any of this.
It only reads, so the SMC here still balances mostly through the CPU.

## Open questions
- Do other T2 models (MacBookPro15,x, 16,2/16,3, 16,4 with the 5600M, iMacs) have the same keys? Reports are
  welcome. The output of `tools/smc-dump.py` (numeric keys only by default) is enough.
- The step sizes (100 MHz / 2.5 W per step) are calibrated by experiment, not decoded. `PZ0T` settles lower
  than on macOS (~34 vs ~53), so the Linux side reacts a bit more strongly than needed.
- `MSAc`/`MSAg`/`MSAi` and the `Q*` keys are not fully understood.
