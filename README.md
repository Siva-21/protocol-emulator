# Protocol Emulator

A programmable protocol emulator ASIC for the Jane Street / Tiny Tapeout
**IHP CMOS5L** shuttle (`ihp-sg13cmos5l`): **8x4 tiles**, **50 MHz**. A host
(for example the demo board's microcontroller) loads programs and exchanges data
with the chip over a 4-pin SPI link. Four programmable sub-cores and a small main
core then drive and sample the remaining I/O pins to emulate serial and parallel
protocols such as UART, SPI and I2C, in controller or target roles.
Project metadata and pinout: [info.yaml](info.yaml), datasheet: [docs/info.md](docs/info.md).

The integrated top `src/tt_um_protocol_emulator/tt_um_protocol_emulator.v` connects all
blocks (integration spec `docs/Integration_spec/Top_level_Integration_Specification_v1.pdf`).
`rtl-checks` checks it as a unit; hardening it (SRAM placement, power grid, timing) is work in progress on branch `pd/sram-integration`; the hardened top is still the placeholder (`src/tt_um_protocol_emulator_placeholder.v`,
listed in `info.yaml`). See [src/README.md](src/README.md) for the blocks and their status.

## Getting started (one-time setup)

1. **Prerequisites:** an x86_64 Linux machine, or Windows with WSL2 (Ubuntu), and
   about **25 GB** of free disk. On WSL2, run everything below inside the WSL
   shell and keep the repo in the WSL file system (`~`), not under `/mnt/c`.
2. **Docker:** install Docker CE ([docs.docker.com/engine/install](https://docs.docker.com/engine/install/);
   on WSL2, Docker CE inside WSL or Docker Desktop with WSL integration). Let your
   user run it without sudo, then log out and back in:
   ```bash
   sudo usermod -aG docker $USER
   docker run --rm hello-world          # must work WITHOUT sudo
   ```
3. **Designs folder:** the container only sees `~/edatools/designs` (mounted as
   `/foss/designs`), so the repo must be cloned **into** it:
   ```bash
   mkdir -p ~/edatools/designs
   cd ~/edatools/designs
   git clone git@github.com:Siva-21/protocol-emulator.git   # or the https:// URL
   cd protocol-emulator
   ```
4. **Image** (~4.5 GB download, 18.7 GB unpacked):
   ```bash
   docker pull ghcr.io/siva-21/pe-verif:2026.10
   ```
5. **Git identity** (once per machine):
   ```bash
   git config --global user.name  "Your Name"
   git config --global user.email "you@example.com"
   ```
6. **Desktop password** (optional): the browser desktop
   (`verification/docker/pe-desktop.sh`) generates one on first use in
   `~/edatools/.vnc_password`; `pe-desktop.sh url` prints the login URL.
7. **First check**, from the repo root; every unit must report `PASS`. The
   container starts in `/foss/designs`, so the script is given by its path there:
   ```bash
   verification/docker/pe-shell.sh /foss/designs/protocol-emulator/scripts/check_rtl_frontend.sh
   ```
8. **Next:** the flows step by step in [docs/WORKFLOWS.md](docs/WORKFLOWS.md),
   branches, commits and PRs in [CONTRIBUTING.md](CONTRIBUTING.md).

## Repository layout

| Path | Contents |
|---|---|
| `src/` | RTL: the hardened Tiny Tapeout top (placeholder for now), the integrated top in `src/tt_um_protocol_emulator/`, and one directory per block, `src/<block>/` |
| `test/` | top-level cocotb test of the Tiny Tapeout top ([test/README.md](test/README.md)) |
| `verification/` | unit tests, formal, regressions, hardening probes, Docker image ([verification/README.md](verification/README.md)) |
| `scripts/` | block checks (frontend, lint, area) and local hardening |
| `docs/` | Tiny Tapeout datasheet ([docs/info.md](docs/info.md)), [workflow guide](docs/WORKFLOWS.md), [toolchain](docs/toolchain.md) and project documentation |
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
scripts: [verification/docker/README.md](verification/docker/README.md); versions,
CI comparison and the checks behind them: [docs/toolchain.md](docs/toolchain.md).

```bash
docker pull ghcr.io/siva-21/pe-verif:2026.10   # once, ~25 GB disk (x86_64)
verification/docker/pe-shell.sh                # shell, repo at /foss/designs/protocol-emulator
```

The start scripts use that image name by default; building it locally instead is
described in [verification/docker/README.md](verification/docker/README.md).

## Running the flows locally

Inside `pe-verif`, from the repo root. Step-by-step guide for every flow
(new block, formal, unit tests, hardening, GitHub): **[docs/WORKFLOWS.md](docs/WORKFLOWS.md)**.


| Flow | Command |
|---|---|
| Block checks | `scripts/check_rtl_frontend.sh`, `scripts/lint_rtl.sh`, `scripts/block_area.sh` (area is informational) |
| Top-level cocotb test | `cd test && make -B` (Verilator), `cd test && make -B SIM=icarus` (`make -C test` does not work: the template Makefile uses `$PWD`) |
| Local hardening (Tiny Tapeout IHP flow: harden, precheck, gate-level test, ~1 h 20 min) | `scripts/harden_local.sh` |
| Harden one block via its probe top | `scripts/harden_local.sh --probe <block>` ([verification/probes/](verification/probes/README.md)) |
| Unit tests, formal, regressions | see [verification/README.md](verification/README.md) |

**Waveforms:** the top-level test writes `test/tb.fst`; open it with
`gtkwave test/tb.fst test/tb.gtkw` or `surfer test/tb.fst` (e.g. in the browser
desktop, `verification/docker/pe-desktop.sh`).

Hardening output: `runs/wokwi/`, the submission (GDS, netlist) in
`tt_submission/`, logs in `runs/harden_local/logs/`. All generated files are git-ignored.

## GitHub checks

These run on every push (and so on every PR branch); all must be green before merging.
`test` and `gds` skip their heavy jobs when a push changes no design or flow files
("Skipped" counts as passing; on `main` they always run), and a newer push cancels
their older run on the same branch. Details: [docs/WORKFLOWS.md](docs/WORKFLOWS.md#github-checks).

| Workflow | What it checks |
|---|---|
| `rtl-checks` | Yosys frontend check, Verilator lint, block area table (job summary) |
| `test` | top-level cocotb test (Verilator, RTL) |
| `docs` | Tiny Tapeout datasheet build from `docs/info.md` |
| `gds` | Tiny Tapeout hardening (LibreLane, `ihp-sg13cmos5l`), then **precheck** and the **gate-level test** on the hardened netlist |

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under the [Apache License 2.0](LICENSE).
