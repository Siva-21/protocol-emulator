# Workflows

Step-by-step guide for every flow in this repo. It assumes:

- the **pe-verif** image is pulled (`docker pull ghcr.io/siva-21/pe-verif:2026.10`) or built
  ([verification/docker/README.md](../verification/docker/README.md)),
- the repo is cloned below `$DESIGNS` (default `~/edatools/designs/protocol-emulator`),
- commands run **inside pe-verif from the repo root** unless a step says otherwise:

```bash
verification/docker/pe-shell.sh          # on the host, from the repo root
cd /foss/designs/protocol-emulator       # inside the container
```

All paths below are relative to the repo root. Replace `<block>` with your
block name (lower case, e.g. `spi_rx`).

Contents:
[Repo hierarchy](#repo-hierarchy) ·
[Adding RTL for a new block](#adding-rtl-for-a-new-block) ·
[Quick lint and elaboration](#quick-lint-and-elaboration) ·
[GitHub checks](#github-checks) ·
[Formal with sby](#formal-with-sby) ·
[Formal trace debug](#formal-trace-debug) ·
[Block cocotb test](#block-cocotb-test) ·
[Plain SV testbench](#plain-sv-testbench-verilator) ·
[Top-level test](#top-level-test) ·
[Hardening, local](#hardening-local) ·
[Hardening, GitHub](#hardening-github) ·
[Which flow when](#which-flow-when) ·
[Scripts and workflows](#scripts-and-workflows) ·
[Not yet available](#not-yet-available)

---

## Repo hierarchy

```
src/                                  RTL that gets hardened
  tt_um_protocol_emulator_placeholder.v   Tiny Tapeout top (plain Verilog)
  <block>/<block>.v ...               one folder per block
  <block>/<block>.f                   file list, paths relative to the repo root
test/                                 top-level cocotb test (TT template: tb.v, test.py, Makefile)
verification/
  docker/                             pe-verif Dockerfile, pe-shell.sh, pe-desktop.sh
  tb/<block>/                         block cocotb test (Makefile, test_<block>.py) and plain SV benches
  formal/<block>/                     <block>.sby, <block>_props.sv
  probes/tt_um_<block>_probe.v        TT wrapper to harden one block on its own
  regress/                            regression runner (to come)
scripts/                              check_rtl_frontend.sh, lint_rtl.sh, block_area.sh, harden_local.sh
docs/                                 info.md (TT datasheet), this guide
software/  flows/                     ISA/assembler/programs; implementation config
info.yaml                             TT project file (top, sources, tiles, clock, pinout)
.github/workflows/                    CI
```

Generated output is git-ignored everywhere: `runs/`, `tt/`, `tt_submission/`,
`.venv*/`, `sim_build/`, `obj_dir/`, `results.xml`, `*.vvp`, `*.log`, `*.vcd`,
`*.fst`, sby work folders. `*.gtkw` (waveform save files) stay tracked.

## Adding RTL for a new block

1. Branch from the latest `main`:
   ```bash
   git switch main && git pull origin main
   git switch -c feature/<block>
   ```
2. Create the block folder and RTL; the top module is named `<block>`:
   ```bash
   mkdir -p src/<block>
   $EDITOR src/<block>/<block>.v
   ```
3. Create the file list (one path per line, relative to the repo root, `#` comments allowed):
   ```bash
   echo src/<block>/<block>.v > src/<block>/<block>.f
   ```
4. Follow the [RTL coding rule](../README.md#rtl-coding-rule): `` `default_nettype none ``
   at the top of each file (and `` `default_nettype wire `` at the end), no implicit
   nets, no SystemVerilog interfaces/modports in `src/`.
5. Run the checks (they find the block through its `.f`):
   ```bash
   scripts/check_rtl_frontend.sh
   scripts/lint_rtl.sh
   scripts/block_area.sh        # informational
   ```
6. Commit with explicit paths, never `git add .`:
   ```bash
   git status
   git add src/<block>/
   git commit -m "feat: add <block>"
   ```
7. Rebase and push, then open a PR into `main` ([CONTRIBUTING.md](../CONTRIBUTING.md)):
   ```bash
   git fetch origin && git rebase origin/main
   git push -u origin feature/<block>
   ```
8. **Do not add the block to `info.yaml`** until it is integrated into the real
   Tiny Tapeout top. `info.yaml` lists only what the top uses; to harden a block
   alone, use its [probe](#probe-one-block).

## Quick lint and elaboration

All blocks plus the TT top:

```bash
scripts/check_rtl_frontend.sh   # Yosys built-in reader, as LibreLane; fails on implicit nets
scripts/lint_rtl.sh             # Verilator --lint-only -Wall
scripts/block_area.sh           # cells / flip-flops / area per block (IHP typ corner)
```

One module by hand:

```bash
# Yosys, exactly like the frontend check (add more read_verilog for more files)
yosys -p "read_verilog -defer -noautowire -sv src/<block>/<block>.v; hierarchy -check -top <block>; stat"

# Verilator lint, all files of the block
verilator --lint-only -Wall --top-module <block> $(sed 's/#.*//' src/<block>/<block>.f)
```

## GitHub checks

1. **What runs:** every push to any branch runs `rtl-checks`, `test`, `docs` and
   `gds` (incl. precheck and gate-level test). `rtl-checks` also runs on
   `pull_request`. Details: [Scripts and workflows](#scripts-and-workflows).
2. **Where:** the PR's *Checks* tab, or the repo's *Actions* tab → workflow → run.
   Each run has a *Summary* page (block area table, linter output, routing and cell
   stats, precheck results) and, at the bottom, **Artifacts** to download:
   `test-results` (tb.fst, results.xml), `tt_submission` (GDS, OAS, LEF, netlist),
   `GDS_logs`, `gds_render` (PNG), `precheck_reports`, `gatelevel_test_results`.
3. **Re-run:** run page → *Re-run jobs* (all or failed). Needs **write access** to
   the repo; without it, ask a maintainer, or push a new commit.
4. **Branch protection on `main`:** no direct pushes; merge only through a PR with
   all required checks green and one approval from someone other than the author
   (set by repo admins in *Settings → Rules*).

## Formal with sby

Example below for a block with ports `clk`, `rst_n`, `en`, `count`, `wrap`.

1. Create the folder:
   ```bash
   mkdir -p verification/formal/<block>
   ```
2. Properties in `verification/formal/<block>/<block>_props.sv`: a module whose
   inputs are the block's ports (and parameters), plus a `bind` that attaches it to
   every instance of `<block>`. The RTL in `src/` stays free of formal code.
   ```systemverilog
   module <block>_props #(parameter [7:0] MAX = 8'd9) (
       input logic clk, rst_n, en,
       input logic [7:0] count,
       input logic wrap
   );
     logic init = 1'b1;                       // first cycle: in reset
     always_ff @(posedge clk) init <= 1'b0;
     always_comb if (init) assume (!rst_n);

     always_ff @(posedge clk) if (!init && rst_n) begin
       a_range: assert (count <= MAX);
       a_wrap:  assert (wrap == (en && count == MAX));
       c_wrap:  cover  (wrap);
     end
   endmodule

   bind <block> <block>_props #(.MAX(MAX)) u_props (.*);
   ```
3. Job file `verification/formal/<block>/<block>.sby`: RTL and properties are read
   with `read_slang` (SystemVerilog, supports `bind`); one task each for bounded
   check, unbounded proof and cover:
   ```ini
   [tasks]
   bmc
   prove
   cover

   [options]
   bmc:   mode bmc
   bmc:   depth 30
   prove: mode prove
   cover: mode cover
   cover: depth 30

   [engines]
   bmc:   smtbmc bitwuzla
   prove: abc pdr
   cover: smtbmc yices

   [script]
   read_slang <block>.v <block>_props.sv --top <block>
   prep -top <block>

   [files]
   # relative to this folder: the files from src/<block>/<block>.f, then the properties
   ../../../src/<block>/<block>.v
   <block>_props.sv
   ```
4. Run **from the block's formal folder** (sby resolves `[files]` against the
   current directory and writes its work folders next to the `.sby`):
   ```bash
   cd verification/formal/<block>
   sby -f <block>.sby            # all tasks
   sby -f <block>.sby prove      # one task
   cd -
   ```
   (`-f` replaces the work folders of a previous run.)

   **Task prefixes:** in a `.sby` file a line prefix selects tasks only if it is
   **one** task name at the very start of the line: `bmc:` or `~bmc:` (every task
   except `bmc`). Several names (`prove bmc:`), commas or indentation are not
   recognised: the line is passed to Yosys as is and fails (e.g. `No such command:
   prove`). For a group of tasks, put a tag after the task in `[tasks]` and use
   the tag as the prefix:
   ```ini
   [tasks]
   prove good
   bmc   good
   bug_bmc

   [script]
   good:    read_slang <block>.v <block>_props.sv --top <block>
   bug_bmc: read_slang -DBUG <block>.v <block>_props.sv --top <block>
   ```
5. Results, in `verification/formal/<block>/<block>_<task>/`:
   - `status`: `PASS` / `FAIL` (exit code 0 / 2), `logfile.txt`: full log;
   - failing assertion: `engine_0/trace.vcd` (counterexample; the log names the
     assertion, file:line and step);
   - cover: `engine_0/trace0.vcd`, `trace1.vcd`, ... one per reached cover statement.

## Formal trace debug

**In the browser desktop** (all tools are in the image):

1. Start the desktop on the host and open it:
   ```bash
   verification/docker/pe-desktop.sh            # on the host, from the repo root
   ```
   Open <http://localhost:8080>, log in with the password from
   `~/edatools/.vnc_password`, open a terminal.
2. Open the trace (failing assertion or cover):
   ```bash
   cd /foss/designs/protocol-emulator/verification/formal/<block>
   gtkwave <block>_bmc/engine_0/trace.vcd &       # counterexample
   surfer  <block>_cover/engine_0/trace0.vcd &    # cover trace
   ```
3. In GTKWave: expand the hierarchy (`<block>` → `u_props`), add signals; the
   failing step is the last one in the trace. *File → Write Save File* stores the
   signal setup as `*.gtkw` (tracked by git, if you want to keep it).
4. Read the source next to the waveform: the log names the failing assertion as
   `file:line` (e.g. `<block>_props.sv:32`); open the properties and the RTL in an
   editor in the desktop (`gedit`, `gvim`; `vim`/`nano` in the terminal):
   ```bash
   gedit <block>_props.sv ../../../src/<block>/<block>.v &
   ```
   Editing works on the host too: `/foss/designs` is your `$DESIGNS` folder.
5. Stop the desktop when done: `verification/docker/pe-desktop.sh stop`.

**On the host instead:** the traces are ordinary files below
`~/edatools/designs/protocol-emulator/verification/formal/<block>/`. Open them with a
GTKWave or Surfer installed on the host, or drag them into the Surfer web app
(<https://app.surfer-project.org>, the file is read locally in the browser).

## Block cocotb test

1. Create `verification/tb/<block>/Makefile` (only `BLOCK` changes per block):
   ```makefile
   BLOCK := <block>
   REPO  := $(abspath ../../..)

   SIM ?= verilator
   TOPLEVEL_LANG = verilog
   # Sources: the block's file list (paths relative to the repo root; # comments allowed).
   VERILOG_SOURCES = $(addprefix $(REPO)/,$(shell sed 's/\#.*//' $(REPO)/src/$(BLOCK)/$(BLOCK).f))
   COCOTB_TOPLEVEL     = $(BLOCK)
   COCOTB_TEST_MODULES = test_$(BLOCK)

   ifeq ($(SIM),verilator)
   EXTRA_ARGS += --timing
   # cocotb's Verilator makefile ignores WAVES; FST tracing is enabled here.
   ifeq ($(WAVES),1)
   EXTRA_ARGS += --trace --trace-fst --trace-structs
   endif
   endif

   include $(shell cocotb-config --makefiles)/Makefile.sim
   ```
2. Tests in `verification/tb/<block>/test_<block>.py`:
   ```python
   import cocotb
   from cocotb.clock import Clock
   from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly

   @cocotb.test()
   async def test_reset(dut):
       cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())   # 50 MHz
       dut.en.value = 0
       dut.rst_n.value = 0
       await ClockCycles(dut.clk, 3)
       dut.rst_n.value = 1
       await RisingEdge(dut.clk)
       await ReadOnly()
       assert dut.count.value == 0
   ```
3. Run from the block's tb folder:
   ```bash
   cd verification/tb/<block>
   make                      # Verilator
   make SIM=icarus           # Icarus
   ```
4. Result: the `TESTS=... PASS=... FAIL=...` table at the end, and `results.xml`.
   Check it in scripts with `python3 -m cocotb_tools.check_results results.xml`.
5. Waveforms (use `-B` to rebuild when switching flags):
   ```bash
   make -B WAVES=1            # Verilator -> verification/tb/<block>/dump.fst
   make -B SIM=icarus WAVES=1 # Icarus    -> verification/tb/<block>/sim_build/<block>.fst
   ```
   View with `gtkwave dump.fst` or `surfer dump.fst` (desktop, see
   [Formal trace debug](#formal-trace-debug)).

## Plain SV testbench (Verilator)

For a quick SystemVerilog bench without cocotb, e.g. `verification/tb/<block>/tb_<block>.sv`
with `$dumpfile("dump.fst"); $dumpvars(0, tb_<block>);` and `$finish`:

1. Build (from the repo root; `--timescale` sets a default for RTL files without
   `` `timescale ``):
   ```bash
   verilator --binary --timing --trace-fst --timescale 1ns/1ps \
     --top-module tb_<block> -Mdir verification/tb/<block>/obj_dir -o tb_<block> \
     $(sed 's/#.*//' src/<block>/<block>.f) verification/tb/<block>/tb_<block>.sv
   ```
2. Run from the tb folder (the FST is written to the current directory):
   ```bash
   cd verification/tb/<block> && ./obj_dir/tb_<block>
   ```
3. View `verification/tb/<block>/dump.fst` with `gtkwave` or `surfer`.

## Top-level test

The Tiny Tapeout template test in `test/` drives the TT top (`tb.v` + `test.py`).
Run it from `test/` (`make -C test` does not work: the template Makefile uses `$PWD`).

1. RTL:
   ```bash
   cd test
   make -B                   # Verilator
   make -B SIM=icarus        # Icarus
   ```
   Waveform: `test/tb.fst` (`gtkwave tb.fst tb.gtkw`), results: `test/results.xml`.
2. Gate level (after a local hardening, which also runs this as its `gl-test` stage):
   ```bash
   cp tt_submission/*.v test/gate_level_netlist.v
   cd test
   make -B GATES=yes PDK_ROOT=$PDK_ROOT_CI/ciel/ihp-sg13/versions/89d42ee6d2fd9b50b86a1aada6fee6673c3e6008
   ```
3. On GitHub: `test` runs the RTL test on every push (artifact `test-results`);
   `gds` → *gl_test* runs the gate-level test on the CI netlist
   (artifact `gatelevel_test_results`).

## Hardening, local

**Keep the machine awake.** A hardening run takes an hour or more, and the
single longest step, Magic DRC of the full 8x4 area, alone takes ~54 min,
even for a small probe. If the laptop suspends (e.g. lid closed), the run just
stops progressing and looks hung. Start long runs from the host with sleep and
the lid switch inhibited:

```bash
# on the host, from the repo root (append --probe <block> to the script for a probe)
systemd-inhibit --what=sleep:handle-lid-switch --why="local hardening" \
  docker run --rm -u "$(id -u):$(id -g)" -v "${DESIGNS:-$HOME/edatools/designs}:/foss/designs:rw" \
  -w /foss/designs/protocol-emulator ghcr.io/siva-21/pe-verif:2026.10 \
  -s bash -c 'TMPDIR=$PWD/runs scripts/harden_local.sh'
```

### Real top

1. Run (first run also clones tt-support-tools into `tt/` and creates `.venv-tt`,
   `.venv-precheck`, about 15 min extra):
   ```bash
   scripts/harden_local.sh
   ```
   Runtime for 8x4 tiles: about **1 h 20 min** (harden ~57 min, precheck ~19 min).
2. Stages: `tt-tools → venvs → user-config → harden → submission → precheck → gl-test`;
   it stops at the first failure. The summary at the end shows:
   - tt-support-tools commit and PDK version,
   - each stage `PASS`/`FAIL` with its time,
   - standard cells, synthesis flip-flops, utilisation,
   - worst setup / hold slack,
   - DRC/LVS counts (Magic, routing, LVS),
   - precheck passed/failed, GDS path, log folder.
3. Outputs: `runs/wokwi/` (LibreLane run; `final/metrics.json`), `tt_submission/`
   (`.gds`, `.oas`, `.lef`, netlist `.v`), `tt/precheck/reports/results.md`, logs
   in `runs/harden_local/logs/<stage>.log`.
4. View the GDS in KLayout (browser desktop) with the IHP layer colours:
   ```bash
   T=$PDK_ROOT_CI/ciel/ihp-sg13/versions/89d42ee6d2fd9b50b86a1aada6fee6673c3e6008/ihp-sg13cmos5l/libs.tech/klayout/tech
   klayout -l $T/sg13cmos5l.lyp tt_submission/*.gds &
   ```

### Probe: one block

> **Untested until the first real block.** `--probe` and the wrapper below have not
> been run through submission and precheck yet; expect to adjust this section then.


1. Write `verification/probes/tt_um_<block>_probe.v`. Rules:
   - plain Verilog, module name `tt_um_<block>_probe`;
   - the standard TT ports (`ui_in`, `uo_out`, `uio_in`, `uio_out`, `uio_oe`, `ena`,
     `clk`, `rst_n`), unchanged;
   - **every input must be used** (LibreLane's disconnected-pin check stays on):
     fold inputs the block does not need into an output, e.g. `^{ui_in[7:1], uio_in}`;
   - drive every output (`uio_oe` included).
   ```verilog
   `default_nettype none
   module tt_um_<block>_probe (
       input  wire [7:0] ui_in,  output wire [7:0] uo_out,
       input  wire [7:0] uio_in, output wire [7:0] uio_out, output wire [7:0] uio_oe,
       input  wire ena, input wire clk, input wire rst_n
   );
     wire [7:0] count;  wire wrap;
     <block> u_blk (.clk(clk), .rst_n(rst_n), .en(ena & ui_in[0]), .count(count), .wrap(wrap));
     assign uo_out  = count;
     assign uio_out = {6'b0, ^{ui_in[7:1], uio_in}, wrap};
     assign uio_oe  = 8'b0000_0011;
   endmodule
   `default_nettype wire
   ```
2. Lint it together with the block:
   ```bash
   verilator --lint-only -Wall --top-module tt_um_<block>_probe \
     verification/probes/tt_um_<block>_probe.v $(sed 's/#.*//' src/<block>/<block>.f)
   ```
3. Harden. The run happens in a temporary copy of the repo (probe first in a
   temporary `info.yaml`, then the files from `<block>.f`); the repo itself is not
   changed. Put the copy under `runs/` so its results survive the container:
   ```bash
   TMPDIR=$PWD/runs scripts/harden_local.sh --probe <block>
   ```
   The gate-level test is skipped (the `test/` bench drives the real top).
   Runtime: like the real top (the probe is hardened on the same 8x4 area):
   harden ~1 h, most of it Magic DRC; precheck ~20 min more.
4. Results: the summary prints the run folder, e.g.
   `runs/harden_probe_<block>.XXXXXX/` with its own `runs/wokwi/`, `tt_submission/`
   and `runs/harden_local/logs/`. Delete the folder when done.

## Hardening, GitHub

### Real top: `gds` workflow

1. Runs on **every push**, any branch: *gds* (LibreLane via `tt-gds-action`,
   `ihp-sg13cmos5l`), then *precheck*, *gl_test* and *viewer* in parallel.
   Expect about the local runtime (an hour or more for 8x4).
2. Results: *Actions → gds → run*. The *Summary* shows linter output, Yosys
   warnings, routing and cell-usage stats, precheck results and the GDS preview.
3. Artifacts: `tt_submission` (GDS, OAS, LEF, netlist), `GDS_logs`, `gds_render`
   (PNG), `precheck_reports`, `gatelevel_test_results`.
4. 3D GDS viewer: the *viewer* job publishes it to GitHub Pages,
   <https://siva-21.github.io/protocol-emulator/> (needs *Settings → Pages → Source:
   GitHub Actions*; the link is also in the run summary).
5. Re-run: *Re-run jobs* on the run page (write access needed).

### One block on GitHub (throwaway branch)

Only when the local probe is not enough (e.g. to compare with CI). **Never merge
this branch, never open a PR from it; delete it afterwards.**

1. Branch and put the probe under `src/`:
   ```bash
   git switch -c harden/<block>
   cp verification/probes/tt_um_<block>_probe.v src/
   ```
2. Edit `info.yaml` temporarily: probe first, then the block's files (relative to `src/`):
   ```yaml
     top_module:  "tt_um_<block>_probe"
     source_files:
       - "tt_um_<block>_probe.v"
       - "<block>/<block>.v"
   ```
3. Commit and push (`gds` starts; the `test` workflow fails on this branch because
   `test/` drives the real top, ignore it):
   ```bash
   git add src/tt_um_<block>_probe.v info.yaml
   git commit -m "TEMP: harden <block> probe (do not merge)"
   git push -u origin harden/<block>
   ```
4. Read the results as for the real top (artifacts, summary).
5. Delete the branch, remote and local:
   ```bash
   git switch main
   git push origin --delete harden/<block>
   git branch -D harden/<block>
   ```

## Which flow when

| Question | Flow | Time |
|---|---|---|
| Rough size of a block, after every RTL change | `scripts/block_area.sh` | seconds |
| Does one block place, route and meet 50 MHz on its own? | `scripts/harden_local.sh --probe <block>` | ~1 h 20 min |
| Will the real top pass Tiny Tapeout (harden, precheck, GL test) before I push? | `scripts/harden_local.sh` | ~1 h 20 min |
| Official result, artifacts, GDS viewer | `gds` workflow (every push) | ~1 h+ |

## Scripts and workflows

| Script | Purpose |
|---|---|
| `scripts/check_rtl_frontend.sh` | read every block and the TT top with Yosys's built-in reader (`-noautowire`), `hierarchy -check`; fails on implicit nets |
| `scripts/lint_rtl.sh` | `verilator --lint-only -Wall` per block and the TT top |
| `scripts/block_area.sh` | per block: cells, flip-flops, area (IHP sg13cmos5l, typ 1.20 V 25 °C); informational |
| `scripts/harden_local.sh` | local TT flow: harden, submission, precheck, gate-level test; `--probe <block>` for one block |
| `verification/docker/pe-shell.sh` | shell (or one command) in pe-verif |
| `verification/docker/pe-desktop.sh` | browser desktop on localhost:8080 (`stop`, `url`) |

| Workflow | Trigger | Jobs / content |
|---|---|---|
| `rtl-checks` | push, pull_request, manual | frontend (yowasp-yosys 0.69), lint (Verilator), block-area (job summary) |
| `test` | push, manual | top-level cocotb test (Verilator, RTL); artifact `test-results` |
| `docs` | push, manual | TT datasheet from `docs/info.md` |
| `gds` | push, manual | gds → precheck, gl_test, viewer (GitHub Pages) |
| `fpga` | manual only (push disabled) | TT template FPGA bitstream, not used |

## Not yet available

- Block cocotb tests (`verification/tb/`) and formal jobs (`verification/formal/`)
  **do not run on GitHub yet**: run them locally before opening a PR. Planned: a
  `verify-smoke` workflow running them inside pe-verif, once the image is
  published to GHCR.
- The regression runner and manifest (`verification/regress/`).
