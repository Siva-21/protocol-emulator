# Verification

Everything that checks the RTL in `src/` without being part of the chip itself.
All flows run in the `pe-verif` image ([docker/](docker/README.md)); the fast
checks also run in GitHub Actions.

| Directory | Contents |
|---|---|
| [docker/](docker/README.md) | `pe-verif` image (Dockerfile) and the shell / desktop launchers |
| [tb/](tb/README.md) | per-block cocotb unit tests: `tb/<block>/` |
| [formal/](formal/README.md) | per-block formal proofs: `formal/<block>/<block>.sby` + `*_props.sv` |
| [regress/](regress/README.md) | regression runner and manifest (to come) |
| [probes/](probes/README.md) | thin TT tops for hardening one block: `probes/tt_um_<block>_probe.v` |

A block is `src/<block>/` with a file list `src/<block>/<block>.f` whose top
module is `<block>`; the scripts discover blocks from those file lists.

## Flows

| Flow | Command (repo root, inside `pe-verif`) | Runs in CI |
|---|---|---|
| Block checks: Yosys frontend, Verilator lint, area estimate | `scripts/check_rtl_frontend.sh`, `scripts/lint_rtl.sh`, `scripts/block_area.sh` | `rtl-checks.yaml` (every push / PR) |
| Top-level test (Tiny Tapeout template) | `make -C test` (Verilator; `SIM=icarus`, `GATES=yes` for gate level) | `test.yaml` |
| Unit tests | `tb/<block>/`, see [tb/](tb/README.md) | to come |
| Formal | `sby -f formal/<block>/<block>.sby`, see [formal/](formal/README.md) | to come |
| Regressions | runner in [regress/](regress/README.md) (to come) | to come |
| Local hardening (TT IHP flow: harden, precheck, gate-level test) | `scripts/harden_local.sh` or `scripts/harden_local.sh --probe <block>` | `gds.yaml` (Tiny Tapeout) |

Generated output (`runs/`, `tt/`, `tt_submission/`, venvs, waveforms,
`verification/reports/`) is git-ignored.
