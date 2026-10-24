# macOS measurement kit

These tools were used to watch macOS handle the same load (see `docs/FINDINGS.md`). They only read,
there are no SMC writes and no `pmset` or SIP changes.

| file | |
|---|---|
| `smcdump.c` | dumps all SMC keys (TSV), once or about once per second in a loop |
| `gpuburn.m` | Metal compute load for N seconds |
| `cpuburn.c` | N threads of busy loops for N seconds |
| `mac-collect.sh` | builds the three, runs idle → GPU → GPU+CPU → cooldown with SMC dumps and `powermetrics`, collects ioreg and kext plists |

They need the Xcode Command Line Tools (`xcode-select --install`). Start the test with
`sudo bash mac-collect.sh`. It takes about 8 minutes and the fans get loud. The result is saved as
`~/Desktop/t2-cruise-mac.tar.gz`.

The result contains the full ioreg and raw SMC dumps, which include serial numbers. Don't post the archive
publicly, share extracted numbers instead.
