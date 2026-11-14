# Toolchain

What the `pe-verif` image contains, why each addition is there, how it compares
with Tiny Tapeout's CI, and what was checked. Build and start the image as
described in [verification/docker/README.md](../verification/docker/README.md);
step-by-step flows are in [WORKFLOWS.md](WORKFLOWS.md).

Contents:
[Base image](#base-image-iic-osic-tools-202610) ·
[pe-verif additions](#derived-image-ghcriosiva-21pe-verif202610) ·
[Environment](#environment-pdk) ·
[LibreLane / PDK bridge](#librelane-and-pdk-bridge-tiny-tapeout-ci-parity) ·
[Local hardening](#local-hardening-check) ·
[Local precheck](#local-precheck-check) ·
[PR #1 interface check](#pr-1-interface-check-featurehost-link)

## Base image: IIC-OSIC-TOOLS 2026.10

- Image: `hpretl/iic-osic-tools:2026.10` (latest release tag on Docker Hub as of 2026-11-10)
- Digest: `sha256:306585de35d198e70ea58950f77147c86f56c698726a19afea9f1c83009557be`
- Source: <https://github.com/iic-jku/IIC-OSIC-TOOLS>, commit `a5fa0c4` (2026-11-09)

Tool versions in the base, probed 2026-11-10 inside the container (uid 1000, nothing installed):

| Tool | Status | Version | Path / notes |
|---|---|---|---|
| yosys | ✅ | 0.70 (git 28ba3cb92) | `/foss/tools/bin/yosys` |
| sby | ✅ | v0.70-dirty | `/foss/tools/bin/sby` |
| eqy | ✅ | v0.70-dirty | `/foss/tools/bin/eqy` |
| mcy | ✅ | — (no version flag) | `/foss/tools/bin/mcy` |
| yices-smt2 | ✅ | Yices 2.7.0 | `/foss/tools/bin/yices-smt2` |
| yosys-abc | ✅ | ABC 1.01 (built 2026-10-15) | `/foss/tools/bin/yosys-abc` |
| z3 | ❌ → added | — | base has only the system `libz3.so.4` |
| bitwuzla | ❌ → added | — | not present |
| boolector | ❌ | — | not present (see below) |
| read_slang | ✅ | — | `help read_slang` works without `-m slang` (slang-yosys-plugin) |
| verilator | ✅ | 5.052 (2026-09-05) | `/foss/tools/bin/verilator` |
| iverilog | ✅ | 14.0 (devel, s20260301-579-g15d870a5) | `/foss/tools/bin/iverilog` |
| sv2v | ✅ | v0.0.13-13-g493a88f | `/foss/tools/bin/sv2v` |
| verible | ✅ | v0.0-4296-g0f262651 | `/foss/tools/bin/verible-verilog-syntax` |
| surfer | ✅ | 0.7.0 | `/foss/tools/bin/surfer` |
| gtkwave | ✅ | 4.0.0-prealpha (f6d60e0) | `/foss/tools/bin/gtkwave` (needs a display) |
| cocotb | ✅ | 2.1.0 | `/usr/local/bin/cocotb-config` |
| pyuvm | ✅ | 5.0.0 | Python package |
| pytest | ✅ | 9.1.1 | `/usr/local/bin/pytest` |
| pytest-xdist | ❌ → added | — | |
| cocotb-coverage | ❌ → added | — | |

## Derived image: ghcr.io/siva-21/pe-verif:2026.10

[verification/docker/Dockerfile](../verification/docker/Dockerfile) on top of the
base; the base itself is unchanged. Default user `1000:1000` (as the base); installs
run as root, then switch back.

- Size: 18.68 GB (`docker images`). Layers added: apt 22 MB (z3, liblz4-dev),
  bitwuzla 4.5 MB, pip 1.5 MB, librelane/ciel 4.1 MB, CI PDK 1.03 GB (982 MB on disk).
- Name: `ghcr.io/siva-21/pe-verif:2026.10`; get it with `docker pull ghcr.io/siva-21/pe-verif:2026.10`
  (no `docker tag` step; the start scripts default to this name).
- Labels: `pe-verif.base-tag=2026.10`, `pe-verif.build-date=2026-11-12`,
  `org.opencontainers.image.source=https://github.com/Siva-21/protocol-emulator` (links the GHCR package to the repo).
- Tag policy: the tag is the base release (`2026.10` = built on `iic-osic-tools:2026.10`).
  Once published, a tag never changes: **every Dockerfile change gets a new tag**
  (e.g. `2026.10-2`), and the `IMAGE` default in `pe-shell.sh` / `pe-desktop.sh` moves
  with it. Details: [verification/docker/README.md](../verification/docker/README.md#tag-policy).
- Current image: ID `ddfd7c481d02` (built 2026-11-14, = the tag above; not yet
  published to GHCR, so rebuilds still keep the tag).
- Local build history: ID `ddfd7c481d02` (2026-11-14, patch header text only, same tag);
  `f0583a948b93` (2026-11-14, + source label);
  `de529115d1ce` (2026-11-12, + liblz4-dev);
  earlier `89cf47360f33` (2026-11-10, LibreLane block) and `5cc0077b598a`.

| Added | Version | Source | smtbmc usable? |
|---|---|---|---|
| z3 | 4.8.12 | apt (Ubuntu 24.04 noble) | ✅ yes |
| liblz4-dev | 1.9.4-1build1.1 | apt (Ubuntu 24.04 noble), added 2026-11-12 | n/a |
| bitwuzla | 0.9.1 | GitHub release `Bitwuzla-Linux-x86_64-static.zip`, sha256-checked | ✅ yes |
| pytest-xdist | 3.8.0 (+ execnet 2.1.2) | pip | |
| cocotb-coverage | 2.0 (+ python-constraint 1.4.0) | pip | |
| pyyaml | 6.0.3 (already in base, unchanged) | pip | |
| librelane | 3.1.0.dev4 (was 3.1.0.dev3), in place, gzip patch re-applied | pip | temporary, see [bridge](#librelane-and-pdk-bridge-tiny-tapeout-ci-parity) |
| ciel | 3.2.0 (was 2.6.1) | pip | temporary, required by librelane dev4 |
| CI PDK ihp-sg13 | `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008` in `/foss/pdks-ci` (`$PDK_ROOT_CI`) | ciel-releases | temporary |

Why:

- **liblz4-dev**: Verilator `--trace-fst` compiles its FST writer (`fstcpp_writer.cpp`)
  into every traced model and links `-llz4 -lz`. The base had only the runtime
  `liblz4-1`, so any FST-traced Verilator build failed with
  `fatal error: lz4.h: No such file or directory`. zlib's headers (`zlib1g-dev`) were
  already in the base. OSS CAD Suite does not ship lz4.h either, so the CI `test`
  workflow installs `liblz4-dev zlib1g-dev` with apt.
- **Boolector is not installed**: Ubuntu noble's package is 1.5.118 (2013), which
  `yosys-smtbmc` cannot drive (`unsupported command 'set-option'`). Bitwuzla is its successor.
- **pip installs** run against a constraints file of every package already in the
  base, so nothing pre-installed changes (cocotb stays 2.1.0; verified by diffing `pip list`).

## Environment (PDK)

The base image defaults to `PDK=ihp-sg13g2`. The launchers
(`verification/docker/pe-shell.sh`, `pe-desktop.sh`) start the container with
`-e PDK=ihp-sg13cmos5l` (variable `PDK` at the top of each script); the image's
startup then derives the rest from `$PDK` under `PDK_ROOT=/foss/pdks`:

| Variable | Value |
|---|---|
| `PDK` | `ihp-sg13cmos5l` |
| `PDKPATH` | `/foss/pdks/ihp-sg13cmos5l` |
| `STD_CELL_LIBRARY` | `sg13cmos5l_stdcell` |
| `KLAYOUT_PATH` | `/headless/.klayout:$PDKPATH/libs.tech/klayout:$PDKPATH/libs.tech/klayout/tech` |
| `SPICE_USERINIT_DIR` | `$PDKPATH/libs.tech/ngspice` |
| `PDK_ROOT_CI` | `/foss/pdks-ci` (image `ENV`, Tiny Tapeout CI PDK) |

No personal `$DESIGNS/.designinit` is needed (the image would still source one
if present). The scripts in `scripts/` set the PDK they need themselves; `test/Makefile`
uses `PDK ?= ihp-sg13cmos5l`, so it relies on `PDK` not being set to another PDK.

## LibreLane and PDK bridge (Tiny Tapeout CI parity)

**Why:** Tiny Tapeout CI for the cmos5l shuttle (tt-gds-action `ttihp27a`) uses
LibreLane 3.1.0.dev4. The base's LibreLane 3.1.0.dev3 / ciel 2.6.1 do not know the
cmos5l family: hardening failed with `Could not find a PDK family for 'ihp-sg13cmos5l'`.

### Versions: pe-verif vs Tiny Tapeout CI (tt-gds-action `ttihp27a`, cmos5l)

CI runs `tt_tool.py --harden` inside LibreLane's own container; the CI column is that
container's tool set.

| Tool | pe-verif | CI | Action |
|---|---|---|---|
| librelane | 3.1.0.dev4 (was dev3) | 3.1.0.dev4 | **upgraded** |
| ciel | 3.2.0 (was 2.6.1) | >=3.2.0 | **upgraded** |
| yosys | 0.70 | 0.69 | keep (newer) |
| eqy / sby | v0.70 / v0.70 | not used | keep |
| openroad-librelane | `dcf36133` (26Q1-1024) | `dcf36133` | keep (same) |
| sta-librelane | OpenSTA `857316ff` (2.7.0) | `857316ff` | keep (same) |
| openroad / sta | `eb14e40b` (26Q4) / 3.1.0 | not used by the flow | keep |
| magic | 8.3.685 | 8.3.677 (cmos5l needs >=8.3.657) | keep (newer) |
| netgen | 1.5.324 | 1.5.323 | keep (newer) |
| klayout | 0.30.12 | 0.30.12 | keep (same) |
| verilator | 5.052 | 5.046 | keep (newer) |
| iverilog | 14.0-devel `15d870a5` | 13.0 (TT build, gl_test) | keep; GL test passes on 14 |
| cocotb | 2.1.0 | 2.0.1 (template `test/requirements.txt`) | keep; GL test passes on 2.1 |
| IHP PDK | `/foss/pdks/ihp-sg13cmos5l` @ `a49358cc` (iic-jku fork, `dev`), unchanged | ciel `ihp-sg13` @ `89d42ee6` | **added** `/foss/pdks-ci` |

### What was changed (temporary Dockerfile blocks)

- **librelane 3.1.0.dev3 → 3.1.0.dev4, ciel 2.6.1 → 3.2.0**, in place in the image's
  own Python (`/usr/bin/python3`, `/usr/local/lib/python3.12/dist-packages`), every
  other installed package pinned by a constraints file. `pip list` diff: only these two
  lines. `pip check`: nothing new. `cace` 2.11.0 still imports (needs `ciel>=0.16.0`).
- **Patch** [`verification/docker/patches/librelane-get-lib-voltage-gzip.patch`](../verification/docker/patches/librelane-get-lib-voltage-gzip.patch)
  (the base's own fix for librelane#627, gzipped Liberty in `get_lib_voltage()`): still
  needed in dev4, re-applied (5-line offset). The build fails if it stops applying.
- **Wrapper** `/foss/tools/bin/librelane` unchanged (puts `openroad-librelane/bin`
  first on PATH, adds `--manual-pdk`); it now runs dev4.
- **CI PDK**: `ihp-sg13` @ `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`, fetched at build
  time with `ciel.fetch` from ciel-releases exactly as LibreLane does, into
  `/foss/pdks-ci/ciel/ihp-sg13/versions/89d42ee…/` (982 MB). It is a commit of
  IHP-GmbH/IHP-Open-PDK (merge of PR #1280 "sync-librelane", 2026-10-16) and the
  `ihp-sg13` entry of dev4's `pdk_hashes.yaml`, which is how CI's LibreLane picks it;
  the build checks that entry. The image's own PDKs in `/foss/pdks` are untouched.
- No binary tool needed an upgrade.

### Notes

- `$PDK_ROOT_CI` is a ciel store: the PDK sits in the versioned directory (no
  `ciel enable` symlink), so plain `$PDK_ROOT/ihp-sg13cmos5l` paths (`test/Makefile`,
  precheck) need `PDK_ROOT` set to the version directory. LibreLane resolves it itself.
- `tt_tool.py` runs `python -m librelane`, bypassing the wrapper; `scripts/harden_local.sh`
  therefore puts `/foss/tools/openroad-librelane/bin` first on PATH, as the wrapper and CI do.
- `pnl.v` (powered netlist) fails the gate-level build with the CI PDK's cell models,
  which declare `VDD`/`VSS` only under `USE_POWER_PINS`; the TT flow uses `nl.v` for IHP.
- sky130/gf180 in `/foss/pdks` were installed by ciel 2.x. Through the `librelane`
  wrapper (`--manual-pdk`) nothing changes; a plain `python -m librelane --pdk sky130A`
  without `--manual-pdk` would now look for dev4's sky130 hash (`792ef670…`).

### Exit condition

When an IIC-OSIC-TOOLS release ships LibreLane >= 3.1.0.dev4 (and ciel >= 3.2.0):
bump `BASE_TAG`, delete the "LibreLane 3.1.0.dev4" and "CI PDK" blocks from the
Dockerfile (and `verification/docker/patches/` if the base carries the fix), rebuild,
rerun the local hardening and precheck checks below. If that release also ships the
CI PDK hash, `PDK_ROOT_CI` can go too.

## Local hardening check

First checked on a standalone copy of the TT IHP template
(ttihp-verilog-template `main` @ `4b1204a`, tt-support-tools `main` @ `9d13ff3`,
example `tt_um_example`, 8x4 tiles, 50 MHz), offline (`--network none`):

- **PASS** (2026-11-10): hardening 3007 s (50 min), create-user-config 23 s,
  gate-level test 3 s.
- Die 1724.16 x 710.64 µm (8x4), core 1,208,170 µm²; 95 standard cells, 0 flip-flops
  (combinational example), 95,385 fill/decap, utilisation 0.072 %.
- Worst slack: setup +10.34 ns (slow 1.08 V 125 °C), hold +7.88 ns (fast).
- Magic DRC 0, route DRC 0, LVS 0, antenna 0, max slew/cap/fanout 0, Verilator lint 0/0.
- KLayout DRC and XOR are not run by TT's config (`RUN_KLAYOUT_DRC` / `RUN_KLAYOUT_XOR`
  false), hence the "klayout__drc_error__count not reported" warning.
- Expected warnings: fallback SDC, `CTS-0041/0082/0083` (no clock nets), `DRT-0349`
  LEF58_ENCLOSURE without CUTCLASS, long-wire threshold not set, `VSRC_LOC_FILES` not
  set, input pins without antenna gate info.

In this repo the same flow is `scripts/harden_local.sh`. On the placeholder top
(2026-11-12): all 7 stages PASS in 79 min (harden 57 min, of which Magic DRC 54 min;
precheck 19 min); 79 cells, 8 flip-flops, setup +14.639 / hold +0.178 ns, DRC/LVS 0,
precheck 10/10. A run only progresses while the machine is awake (see
[WORKFLOWS.md](WORKFLOWS.md#hardening-local)).

## Local precheck check

**PASS, 10/10** (2026-11-10, offline), on the 8x4 example above. Runtime 1147 s
(~19 min, mostly KLayout DRC). Mirrors CI's precheck job (tt-gds-action `ttihp27a`,
`precheck/action.yml`), which pins the same PDK for cmos5l (`89d42ee6…`).

| Check | Result |
|---|---|
| KLayout pin label overlapping drawing | ✅ |
| KLayout SG13CMOS5L DRC | ✅ (0 errors, 33 checks) |
| KLayout zero area | ✅ |
| KLayout Checks | ✅ |
| Pin check | ✅ |
| Boundary check (template `tt_block_8x4_pgvdd.def`) | ✅ |
| Layer check | ✅ |
| Cell name check | ✅ |
| Analog pin check | ✅ |
| Verilog syntax check (yowasp-yosys 0.63) | ✅ |

| Tool | Local | CI (nix, `tt/precheck/tool-versions.json`) |
|---|---|---|
| KLayout | 0.30.12 (image) | 0.30.4 |
| Magic | 8.3.685 (image) | 8.3.568 |
| KLayout Python module | 0.30.12 (image; requirements accept `>=0.30.8,<0.31`) | from pip, same range |
| numpy / gdstk / pyyaml | 1.26.4 / 0.9.52 / 6.0.1 (venv, same pins as CI) | same |
| yowasp-yosys | 0.63.0.0.post1107 (venv) | same |
| Python | 3.12 (image) | 3.11 |
| PDK | `/foss/pdks-ci` ihp-sg13 @ `89d42ee6…` | same hash |

Notes (all handled by `scripts/harden_local.sh`):

- Precheck runs from a venv (`.venv-precheck`, `pip install -r tt/precheck/requirements.txt`)
  whose site-packages must go **first** on `PYTHONPATH`: otherwise the image's numpy
  2.5.4 loads and the venv's gdstk 0.9.52 (built for numpy 1.x) fails to import.
- Pass `--gds` as an **absolute** path, as CI does: precheck passes the directory to
  yowasp-yosys as `YOWASP_MOUNT`, which must be absolute; with a relative path the
  Verilog syntax check fails (9/10).
- `PDK_ROOT` must be the ciel version directory (precheck reads `$PDK_ROOT/$PDK/...`).
- Local covers all three CI jobs (gds, gl_test, precheck). Remaining difference: newer
  KLayout/Magic/Yosys locally, so results close to a limit may differ.

## PR #1 interface check (`feature/host-link`)

Question: do the PR's SystemVerilog interfaces/modports (`rtl/bus_def/*_if.sv`, used by
`rtl/host_link/*.sv`) go through the Tiny Tapeout IHP template flow unchanged?
Checked 2026-11-10 in `pe-verif:2026.10` at PR head `25ea22d` (read-only; the PR branch
was not modified), with a probe top `tt_um_hl_probe` (TT ports outside, PR interfaces
inside; expected 48 flip-flops = sync 7 + ctrl 9 + dp 32).

**Answer: not with the template defaults.** The interface code fails Yosys's native
frontend, which both tt_tool's port check and LibreLane (default `USE_SLANG: false`)
use. It works only with (a) a plain-Verilog `tt_um_*` top listed first in
`source_files` and (b) `"USE_SLANG": true` in `src/config.json`. **Decision
(2026-11-10): don't change the template config; interfaces are not supported in `src/`**
(see the [RTL coding rule](../README.md#rtl-coding-rule)).

The failing construct: driving interface members from the module that instantiates the
interface, e.g. `assign cr.clk = clk;` →
`ERROR: Identifier '\cr.clk' is implicitly declared and 'default_nettype is set to none.`

### Tools

| Tool | Result | Flip-flops |
|---|---|---|
| Yosys native `read_verilog -sv` (LibreLane default) | ❌ FAIL (error above) | n/a |
| Yosys `read_slang` (built in, Yosys 0.70) | ✅ PASS | 48 |
| Verilator 5.052 `--lint-only -Wall` | ✅ PASS, 0 warnings | n/a |
| Icarus 14.0-devel `-g2012` | ✅ PASS | n/a |
| sv2v | ✅ PASS | n/a |
| Yosys after sv2v | ✅ PASS | 48 |

### TT flow

Template + tt-support-tools `9d13ff3`, PR RTL in `src/`, 8x4 / 50 MHz,
`"USE_SLANG": true` in the user-editable part of `src/config.json`, CI LibreLane
3.1.0.dev4 + CI PDK, offline.

| Step | Result |
|---|---|
| `--create-user-config`, probe as top (interface code in the top file) | ❌ FAIL: tt_tool `check_ports()` reads the top with yowasp-yosys `read_verilog -lib -sv` (native, ignores `USE_SLANG`): same `\cr.clk` error. CI would fail the same way. |
| Plain-Verilog top listed **first** + interface code in a second file | ✅ port check passes (it reads only the first file) |
| Native read of the split sources (= LibreLane with `USE_SLANG: false`) | ❌ FAIL: same `\cr.clk` error |
| `--harden` with `USE_SLANG: true` | Stopped by decision at Magic DRC. Synthesis through slang: **48 flip-flops**, 197 cells; placement and routing completed. |
| Precheck, gate-level test, eqy | Not run (stopped) |

### Options if interfaces were wanted in synthesised RTL

1. `"USE_SLANG": true` (one line, user-editable section; slang is "not as battle-tested"
   per LibreLane) plus a plain top listed first.
2. sv2v-convert to plain Verilog and commit the generated file (template unchanged).
3. Plain ports at the TT boundary (no interfaces in synthesised RTL; keep them in
   verification code). Template unchanged, no extra frontend or conversion. **Chosen.**

In every option the `tt_um_*` top file must stay plain Verilog.
