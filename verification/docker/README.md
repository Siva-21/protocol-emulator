# pe-verif image

[IIC-OSIC-TOOLS](https://github.com/iic-jku/IIC-OSIC-TOOLS) `2026.10` plus the
verification and Tiny Tapeout pieces it lacks. Every flow in
[verification/](../README.md) and `scripts/` runs in it.

| File | Purpose |
|---|---|
| `Dockerfile` | the image |
| `patches/librelane-get-lib-voltage-gzip.patch` | gzip-Liberty fix re-applied to LibreLane (used by the Dockerfile) |
| `pe-shell.sh` | shell (or one command) in the image |
| `pe-desktop.sh` | browser desktop (noVNC) on `localhost` |

## Contents

Base: `hpretl/iic-osic-tools:2026.10`
(`sha256:306585de35d198e70ea58950f77147c86f56c698726a19afea9f1c83009557be`),
which already has Yosys 0.70, SymbiYosys, Verilator 5.052, Icarus, cocotb 2.1.0,
KLayout, Magic, Netgen, OpenROAD and the IHP PDKs in `/foss/pdks`. Added:

| Added | Version | Source | Why |
|---|---|---|---|
| z3 | 4.8.12 | apt (Ubuntu 24.04) | SMT solver for `yosys-smtbmc` |
| liblz4-dev | 1.9.4 | apt (Ubuntu 24.04) | Verilator `--trace-fst` (lz4.h, -llz4) |
| bitwuzla | 0.9.1 | GitHub release, sha256-checked | SMT solver (Boolector's successor) |
| pytest-xdist | 3.8.0 | pip | parallel test runs |
| cocotb-coverage | 2.0 | pip | functional coverage |
| pyyaml | 6.0.3 (unchanged) | pip | scripts read `info.yaml` |
| librelane | 3.1.0.dev4 (base: dev3), gzip patch re-applied | pip, in place | Tiny Tapeout CI parity for `ihp-sg13cmos5l` (temporary) |
| ciel | 3.2.0 (base: 2.6.1) | pip, in place | required by librelane dev4 (temporary) |
| CI PDK `ihp-sg13` | `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008` in `/foss/pdks-ci` (`$PDK_ROOT_CI`) | ciel-releases | the PDK version TT CI uses; offline hardening (temporary) |

Full version tables (base and additions), the comparison with Tiny Tapeout CI and
the local hardening/precheck checks: [docs/toolchain.md](../../docs/toolchain.md).

Every other package of the base is pinned to its installed version during the
build (pip constraints file), so nothing else changes. The temporary block
(librelane, ciel, CI PDK) goes away once an IIC-OSIC-TOOLS release ships
librelane >= 3.1.0.dev4: then only `BASE_TAG` is bumped.

Default user `1000:1000`, as in the base.

## Requirements

- **x86_64** host with Docker. On ARM (e.g. Apple Silicon) build the image
  locally; a published image will be x86_64 only.
- **~25 GB free disk**: the image is 18.7 GB, plus build headroom.

## Get the image

Pull it from GHCR (x86_64; ~4.5 GB download, 18.7 GB unpacked). The start
scripts use this name by default, so no `docker tag` step is needed:

```bash
docker pull ghcr.io/siva-21/pe-verif:2026.10
```

Or build it yourself from the repo root under the same name:

```bash
docker build -t ghcr.io/siva-21/pe-verif:2026.10 verification/docker
```

The Dockerfile's `org.opencontainers.image.source` label links the GHCR package
to this repository.

## Start

Both scripts mount `$DESIGNS` (default `$HOME/edatools/designs`) at
`/foss/designs` and run as your UID/GID, so files you write there stay yours.
This repo is expected below `$DESIGNS`. Both set `PDK=ihp-sg13cmos5l` in the
container (the base defaults to ihp-sg13g2); the image derives `PDKPATH`,
`STD_CELL_LIBRARY`, `KLAYOUT_PATH` and `SPICE_USERINIT_DIR` from it, so no personal
`.designinit` is needed. All settings are variables at the top of each script and
can be overridden from the environment (`DESIGNS`, `IMAGE`, `PDK`, ...).

Shell (removed on exit; a second call joins the open shell):

```bash
verification/docker/pe-shell.sh
```

One command:

```bash
verification/docker/pe-shell.sh bash -c 'cd /foss/designs/protocol-emulator && scripts/lint_rtl.sh'
```

Desktop on `http://localhost:8080` (`WEB_PORT`), bound to `127.0.0.1` only. The
password is generated on first use into `$HOME/edatools/.vnc_password`
(`PASSWORD_FILE`, mode 600):

```bash
verification/docker/pe-desktop.sh         # start
verification/docker/pe-desktop.sh url     # login URL (contains the password)
verification/docker/pe-desktop.sh stop    # stop and remove
```

## Tag policy

- The tag is the base release: `ghcr.io/siva-21/pe-verif:2026.10` is built on `iic-osic-tools:2026.10`.
- **Until the first GHCR publish**: a rebuild keeps the same tag.
- **After the first publish** (`ghcr.io/siva-21/pe-verif:2026.10`): every
  Dockerfile change bumps the tag (e.g. `2026.10-2`), so a published tag never
  changes. Bump the `IMAGE` default in `pe-shell.sh` and `pe-desktop.sh` with it
  (or set `IMAGE=ghcr.io/siva-21/pe-verif:<tag>` for a one-off).
