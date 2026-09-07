# Generic simulation scripts

Source **vset**, then use **xelab** and **xsim**. The Vivado IDE is not launched.

| | Path |
|--|------|
| Env (source) | `vset` |
| Compile / elaborate | `xelab` |
| Simulate + waveform | `xsim` |
| Helpers | `sim_lib.sh` (sourced only) |
| RTL | `rtl/<variant>/` (set by `vset`; `xelab` compiles the DUT and its `work.*` deps only) |
| Testbenches | `sim/tb/<variant>/**/*_tb.vhd` |
| Scripts | `sim/scripts/` |
| Elaborated design | `sim/work/` |
| Testbench outputs | `sim/internal/` |

```bash
source sim/scripts/vset
source sim/scripts/vset mmu_branch_v1
xelab pc
xsim
```

`xsim` runs the snapshot (`run 1ms` by default) and opens a live waveform window. `xsim -Batch` runs headless (no GUI).

`xelab` and `xsim` require `vset` in that shell.

From **PowerShell**:

```powershell
wsl -e bash -lc "source sim/scripts/vset && xelab pc && xsim"
```
