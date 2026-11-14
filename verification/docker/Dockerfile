# pe-verif: IIC-OSIC-TOOLS plus the verification packages it lacks.
#
# Build:  docker build -t ghcr.io/siva-21/pe-verif:2026.10 verification/docker
#
# Adds: z3 + liblz4-dev (apt; lz4 for Verilator FST traces), bitwuzla (static release binary),
#       pytest-xdist, cocotb-coverage, pyyaml (pip),
#       librelane 3.1.0.dev4 + ciel 3.2.0 (in place) and the TT CI ihp-sg13 PDK
#       in /foss/pdks-ci (temporary, see the block near the end).
# Boolector is deliberately not installed: Ubuntu noble ships 1.5.118 (2013),
# which yosys-smtbmc cannot drive. Use bitwuzla, its successor.
# Everything already in the base image (e.g. cocotb 2.1.0) stays as is.

ARG BASE_TAG=2026.10
FROM hpretl/iic-osic-tools:${BASE_TAG}

ARG BASE_TAG=2026.10
ARG BITWUZLA_VERSION=0.9.1
ARG BITWUZLA_SHA256=057f1546ae2068df57beb178f3eeab1678f0e5f0c378787a05b7bb294617c9c6

LABEL org.opencontainers.image.title="pe-verif" \
      org.opencontainers.image.description="IIC-OSIC-TOOLS with z3, bitwuzla, pytest-xdist, cocotb-coverage, pyyaml, librelane 3.1.0.dev4 + CI ihp-sg13 PDK" \
      org.opencontainers.image.base.name="hpretl/iic-osic-tools:${BASE_TAG}" \
      org.opencontainers.image.created="2026-11-12" \
      pe-verif.base-tag="${BASE_TAG}" \
      pe-verif.build-date="2026-11-12"

USER root

# From Ubuntu 24.04 (noble):
# - z3: SMT solver.
# - liblz4-dev: Verilator --trace-fst compiles its FST writer into the model and
#   links -llz4 (needs lz4.h + liblz4.so); the base has only the runtime liblz4-1.
#   FST also needs zlib, whose headers (zlib1g-dev) the base already ships.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends z3 liblz4-dev \
 && rm -rf /var/lib/apt/lists/*

# Bitwuzla: official static Linux x86_64 release binary, checksum-verified.
RUN set -eux; \
    tmp="$(mktemp -d)"; \
    curl -fsSL -o "$tmp/bitwuzla.zip" \
      "https://github.com/bitwuzla/bitwuzla/releases/download/${BITWUZLA_VERSION}/Bitwuzla-Linux-x86_64-static.zip"; \
    echo "${BITWUZLA_SHA256}  $tmp/bitwuzla.zip" | sha256sum -c -; \
    unzip -q "$tmp/bitwuzla.zip" -d "$tmp"; \
    install -m 0755 "$tmp/Bitwuzla-Linux-x86_64-static/bin/bitwuzla" /usr/local/bin/bitwuzla; \
    rm -rf "$tmp"

# Python packages. The base pip config already sets break-system-packages;
# the flag is repeated here so the build does not depend on that. The
# constraints file pins every already-installed package to its current
# version, so pip cannot upgrade or downgrade anything (cocotb stays 2.1.0).
RUN set -eux; \
    pip list --format=freeze > /tmp/base-constraints.txt; \
    pip install --no-cache-dir --break-system-packages \
      -c /tmp/base-constraints.txt \
      pytest-xdist cocotb-coverage pyyaml; \
    rm -f /tmp/base-constraints.txt

# --- LibreLane 3.1.0.dev4 (Tiny Tapeout CI parity for ihp-sg13cmos5l) -------
# TEMPORARY. The base ships librelane 3.1.0.dev3 + ciel 2.6.1, which do not know
# the ihp-sg13cmos5l PDK family. Tiny Tapeout CI (tt-gds-action, cmos5l) uses
# librelane 3.1.0.dev4 (requires ciel>=3.2.0). Upgraded in place in the image's
# own Python (system /usr/bin/python3, /usr/local/lib/python3.12/dist-packages);
# every other installed package is pinned by the constraints file, so only
# librelane and ciel change. The /foss/tools/bin/librelane wrapper
# (openroad-librelane on PATH, --manual-pdk) is left untouched and keeps working.
# DROP this block (and the CI PDK below) once an IIC-OSIC-TOOLS release ships
# librelane >= 3.1.0.dev4: bump BASE_TAG instead.
ARG LIBRELANE_VERSION=3.1.0.dev4
ARG CIEL_VERSION=3.2.0
COPY patches/librelane-get-lib-voltage-gzip.patch /tmp/librelane-get-lib-voltage-gzip.patch
RUN set -eux; \
    pip list --format=freeze | grep -v -i -E '^(librelane|ciel)==' > /tmp/base-constraints.txt; \
    pip install --no-cache-dir --break-system-packages \
      -c /tmp/base-constraints.txt \
      "librelane==${LIBRELANE_VERSION}" "ciel==${CIEL_VERSION}"; \
    # Re-apply the base image's gzip-Liberty fix (librelane/librelane#627),
    # still needed in dev4. Not forgiving on purpose: if it stops applying, the
    # build fails and the patch must be re-checked.
    LIBRELANE_SITE="$(python3 -c 'import importlib.util as u, os; print(os.path.dirname(os.path.dirname(u.find_spec("librelane").origin)))')"; \
    patch -p0 --batch -r - -d "$LIBRELANE_SITE" < /tmp/librelane-get-lib-voltage-gzip.patch; \
    python3 -m py_compile "$LIBRELANE_SITE/librelane/common/toolbox.py"; \
    rm -f /tmp/base-constraints.txt /tmp/librelane-get-lib-voltage-gzip.patch

# CI PDK: ihp-sg13 at the hash pinned in librelane 3.1.0.dev4's pdk_hashes.yaml,
# fetched exactly as librelane does at run time (ciel.fetch, ciel-releases static
# web source, default libraries), so hardening is offline and identical for
# everyone. Separate root, so the image's /foss/pdks (incl. its own
# ihp-sg13cmos5l) is untouched. Use with PDK_ROOT=/foss/pdks-ci.
ARG CI_IHP_PDK_HASH=89d42ee6d2fd9b50b86a1aada6fee6673c3e6008
ENV PDK_ROOT_CI=/foss/pdks-ci
RUN set -eux; \
    grep -qx "ihp-sg13: ${CI_IHP_PDK_HASH}" "$(python3 -c 'import librelane, os; print(os.path.dirname(librelane.__file__))')/pdk_hashes.yaml"; \
    mkdir -p "${PDK_ROOT_CI}"; \
    python3 -c "import ciel, sys; from ciel.source import StaticWebDataSource; v = ciel.fetch(str(ciel.get_ciel_home(sys.argv[1])), 'ihp-sg13cmos5l', sys.argv[2], data_source=StaticWebDataSource('https://fossi-foundation.github.io/ciel-releases'), include_libraries=['default']); print(v.get_dir(str(ciel.get_ciel_home(sys.argv[1]))))" \
      "${PDK_ROOT_CI}" "${CI_IHP_PDK_HASH}"; \
    rm -rf /root/.cache /tmp/*; \
    chmod -R a+rX "${PDK_ROOT_CI}"

# Back to the base image's default user.
USER 1000:1000

# Links the GHCR package (ghcr.io/siva-21/pe-verif) to its repository. Kept as
# the last instruction so adding it reuses every cached layer above.
LABEL org.opencontainers.image.source="https://github.com/Siva-21/protocol-emulator"
