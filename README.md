# Protocol Emulator

A programmable protocol emulator ASIC for the Jane Street / Tiny Tapeout
**IHP CMOS5L** shuttle (`ihp-sg13cmos5l`): **8x4 tiles**, **50 MHz**. A host
talks to the chip over SPI; the chip emulates a target protocol on its I/O pins.
Project metadata and pinout: [info.yaml](info.yaml), datasheet: [docs/info.md](docs/info.md).

The design is in progress: the Tiny Tapeout top is currently a placeholder
(`src/tt_um_protocol_emulator_placeholder.v`).

## Repository layout

| Path | Contents |
|---|---|
| `src/` | RTL that gets hardened: the Tiny Tapeout top and one directory per block, `src/<block>/` |
| `test/` | top-level cocotb test of the Tiny Tapeout top ([test/README.md](test/README.md)) |
| `verification/` | unit tests, formal, regressions, hardening probes, Docker image ([verification/README.md](verification/README.md)) |
| `scripts/` | block checks (frontend, lint, area) and local hardening |
| `docs/` | Tiny Tapeout datasheet ([docs/info.md](docs/info.md)) and project documentation |
| `software/` | ISA, assembler and programs |
| `flows/` | ASIC implementation and tool-flow configuration |
| `info.yaml` | Tiny Tapeout project file: top module, source files, tiles, clock, pinout |
| `.github/workflows/` | CI (see [GitHub checks](#github-checks)) |

## RTL coding rule

- `src/` must pass Yosys's built-in Verilog reader (what LibreLane and Tiny
  Tapeout use) with `` `default_nettype none ``: no implicitly declared nets.
  `scripts/check_rtl_frontend.sh` fails on them.
- No SystemVerilog interfaces or modports in `src/` (Yosys's reader does not
  support them). They are fine in `verification/`.
- The Tiny Tapeout top (`tt_um_*`) stays plain Verilog.
- One block per directory: `src/<block>/` with a file list `src/<block>/<block>.f`;
  the block's top module is named `<block>`. The scripts find blocks through these files.

## Toolchain

Everything runs in the **pe-verif** Docker image (IIC-OSIC-TOOLS plus the
verification extras and the Tiny Tapeout CI PDK). Contents, build and start
scripts: [verification/docker/README.md](verification/docker/README.md).

```bash
docker build -t pe-verif:2026.10 verification/docker   # once, ~25 GB disk
verification/docker/pe-shell.sh                        # shell, repo at /foss/designs/protocol-emulator
```

## Running the flows locally

Inside `pe-verif`, from the repo root:

| Flow | Command |
|---|---|
| Block checks | `scripts/check_rtl_frontend.sh`, `scripts/lint_rtl.sh`, `scripts/block_area.sh` (area is informational) |
| Top-level cocotb test | `make -B -C test` (Verilator), `make -B -C test SIM=icarus` |
| Local hardening (Tiny Tapeout IHP flow: harden, precheck, gate-level test, ~1.5 h) | `scripts/harden_local.sh` |
| Harden one block via its probe top | `scripts/harden_local.sh --probe <block>` ([verification/probes/](verification/probes/README.md)) |
| Unit tests, formal, regressions | see [verification/README.md](verification/README.md) |

**Waveforms:** the top-level test writes `test/tb.fst`; open it with
`gtkwave test/tb.fst test/tb.gtkw` or `surfer test/tb.fst` (e.g. in the browser
desktop, `verification/docker/pe-desktop.sh`).

Hardening output: `runs/wokwi/`, the submission (GDS, netlist) in
`tt_submission/`, logs in `runs/harden_local/logs/`. All generated files are git-ignored.

## GitHub checks

These run on every push (and so on every PR branch); all must be green before merging:

| Workflow | What it checks |
|---|---|
| `rtl-checks` | Yosys frontend check, Verilator lint, block area table (job summary). Also runs on `pull_request`. |
| `test` | top-level cocotb test (Verilator, RTL) |
| `docs` | Tiny Tapeout datasheet build from `docs/info.md` |
| `gds` | Tiny Tapeout hardening (LibreLane, `ihp-sg13cmos5l`), then **precheck** and the **gate-level test** on the hardened netlist |

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under the [Apache License 2.0](LICENSE).
