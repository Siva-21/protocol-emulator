#!/usr/bin/env bash
# Informational area estimate per RTL unit: Yosys built-in reader, generic
# synthesis, then mapping to the IHP sg13cmos5l standard cells (typical corner):
#   read_verilog -sv <file>...; synth -flatten -top <top>;
#   dfflibmap -liberty L; abc -liberty L; stat -liberty L
# Units: each src/<block>/<block>.f (top module <block>) plus the Tiny Tapeout
# top from info.yaml. Prints unit | cells | flip-flops | area (um^2).
# Fails only if synthesis of a unit fails; the numbers are not checked.
#
#   scripts/block_area.sh                    (env: YOSYS=yosys, LIBERTY=<.lib or .lib.gz>)
#
# Default Liberty: the Tiny Tapeout CI PDK baked into pe-verif ($PDK_ROOT_CI,
# ihp-sg13 @ CI_IHP_PDK_HASH, see TOOLCHAIN.md "Local hardening").
set -euo pipefail

YOSYS=${YOSYS:-yosys}
CI_IHP_PDK_HASH=${CI_IHP_PDK_HASH:-89d42ee6d2fd9b50b86a1aada6fee6673c3e6008}
LIBERTY=${LIBERTY:-${PDK_ROOT_CI:-/foss/pdks-ci}/ciel/ihp-sg13/versions/$CI_IHP_PDK_HASH/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib}
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Print one line per unit: "<name>\t<top>\t<file> <file> ..." (paths relative
# to the repo root). Units: every src/<block>/<block>.f (top module <block>),
# then the Tiny Tapeout top from info.yaml. Exits non-zero on a broken .f or
# info.yaml (a listed file that doesn't exist is reported by the unit's check).
list_units() {
	python3 - <<'PY'
import glob, os, sys, yaml
units = []
for flist in sorted(glob.glob("src/*/*.f")):
    block = os.path.basename(os.path.dirname(flist))
    if os.path.basename(flist) != f"{block}.f":
        continue
    files = []
    with open(flist) as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if line:
                files.append(line)
    if not files:
        sys.exit(f"{flist}: no source files listed")
    units.append((block, block, files))
with open("info.yaml") as fh:
    project = yaml.safe_load(fh)["project"]
top = project["top_module"]
units.append((f"tt_top:{top}", top, [os.path.join("src", f) for f in project["source_files"]]))
for name, top, files in units:
    print(f"{name}\t{top}\t{' '.join(files)}")
PY
}

# Fail early, per unit, on files listed but missing.
missing_files() {
	local f out=""
	for f in $1; do [ -f "$f" ] || out+=" $f"; done
	printf '%s' "$out"
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$LIBERTY" ]; then
	echo "ERROR: Liberty file not found: $LIBERTY (set LIBERTY=...)" >&2
	exit 2
fi
lib=$LIBERTY
case "$LIBERTY" in
	*.gz) lib=$tmp/stdcell.lib; gzip -dc "$LIBERTY" > "$lib" ;;
esac
echo "Liberty: $LIBERTY"

# Sequential cells (those with an ff or latch group) in this library.
python3 - "$lib" > "$tmp/seq_cells" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
starts = [(m.start(), m.group(1)) for m in re.finditer(r'\bcell\s*\(\s*"?([^")\s]+)"?\s*\)', text)]
for i, (pos, name) in enumerate(starts):
    body = text[pos:starts[i + 1][0] if i + 1 < len(starts) else len(text)]
    if re.search(r'\b(ff|latch|ff_bank|latch_bank)\s*\(', body):
        print(name)
PY

units=$(list_units)
fails=0
printf '%-40s %8s %11s %14s\n' "unit" "cells" "flip-flops" "area (um^2)"
while IFS=$'\t' read -r name top files; do
	miss=$(missing_files "$files")
	if [ -n "$miss" ]; then
		printf '%-40s FAIL (missing:%s)\n' "$name" "$miss"; fails=$((fails + 1)); continue
	fi
	cmd=""
	for f in $files; do cmd+="read_verilog -sv $f; "; done
	cmd+="synth -flatten -top $top; dfflibmap -liberty $lib; abc -liberty $lib; opt_clean; "
	cmd+="tee -q -o $tmp/stat.json stat -json -liberty $lib"
	if ! "$YOSYS" -q -p "$cmd" > "$tmp/log" 2>&1; then
		printf '%-40s FAIL (synthesis)\n' "$name"
		grep -m 5 -E "ERROR|Error" "$tmp/log" | sed 's/^/      /' || tail -n 5 "$tmp/log" | sed 's/^/      /'
		fails=$((fails + 1)); continue
	fi
	python3 - "$tmp/stat.json" "$tmp/seq_cells" "$top" "$name" <<'PY'
import json, sys
stat = json.load(open(sys.argv[1]))
seq = set(open(sys.argv[2]).read().split())
top, name = sys.argv[3], sys.argv[4]
mod = stat["modules"].get("\\" + top) or stat.get("design", {})
by_type = mod.get("num_cells_by_type", {})
ffs = sum(n for t, n in by_type.items() if t.lstrip("\\") in seq)
area = mod.get("area", 0.0)
print(f"{name:<40} {mod.get('num_cells', 0):>8} {ffs:>11} {area:>14.2f}")
PY
done <<< "$units"

[ "$fails" -eq 0 ]
