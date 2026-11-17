#!/usr/bin/env bash
# Informational area estimate per RTL unit: Yosys built-in reader, generic
# synthesis, then mapping to the IHP sg13cmos5l standard cells (typical corner):
#   read_verilog -sv <file>...; synth -flatten -top <top>;
#   dfflibmap -liberty L; abc -liberty L; stat -liberty L
# Units: each src/<block>/<block>.f (top module <block>) plus the Tiny Tapeout
# top from info.yaml. Prints unit | cells | flip-flops | area (um^2).
# Fails only if synthesis of a unit fails; the numbers are not checked.
# Hard macros (black boxes in verification/stubs/*.v, e.g. the SRAM) are not
# in the table's area. After the table, for every unit that instantiates one,
# the macro area (LEF SIZE, from $PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/lef/
# or else the PDK of the Liberty file) and the total with macros are printed;
# without the LEF: "macro area: PDK not available".
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

# Scratch dir inside the repo (runs/ is git-ignored), not /tmp: yowasp-yosys
# (used in CI) maps /tmp to its own private sandbox directory, so files it
# writes there (stat.json) would not be visible here.
mkdir -p runs
tmp=$(mktemp -d "$PWD/runs/block_area.XXXXXX"); trap 'rm -rf "$tmp"' EXIT

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
# Hard-macro module names: the black boxes in verification/stubs/*.v.
macro_names=$(sed -n 's/^[[:space:]]*module[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_$]*\).*/\1/p' verification/stubs/*.v 2>/dev/null | tr '\n' ' ' || true)
fails=0
printf '%-40s %8s %11s %14s\n' "unit" "cells" "flip-flops" "area (um^2)"
while IFS=$'\t' read -r name top files; do
	miss=$(missing_files "$files")
	if [ -n "$miss" ]; then
		printf '%-40s FAIL (missing:%s)\n' "$name" "$miss"; fails=$((fails + 1)); continue
	fi
	cmd=""
	for f in verification/stubs/*.v; do [ -f "$f" ] && cmd+="read_verilog -lib -sv $f; "; done
	for f in $files; do cmd+="read_verilog -sv $f; "; done
	cmd+="synth -flatten -top $top; dfflibmap -liberty $lib; abc -liberty $lib; opt_clean; "
	cmd+="tee -q -o $tmp/stat.json stat -json -liberty $lib"
	if ! "$YOSYS" -q -p "$cmd" > "$tmp/log" 2>&1; then
		printf '%-40s FAIL (synthesis)\n' "$name"
		grep -m 5 -E "ERROR|Error" "$tmp/log" | sed 's/^/      /' || tail -n 5 "$tmp/log" | sed 's/^/      /'
		fails=$((fails + 1)); continue
	fi
	python3 - "$tmp/stat.json" "$tmp/seq_cells" "$top" "$name" "$tmp/macros.tsv" "$macro_names" <<'PY'
import json, sys
stat = json.load(open(sys.argv[1]))
seq = set(open(sys.argv[2]).read().split())
top, name = sys.argv[3], sys.argv[4]
macros = set(sys.argv[6].split())
mod = stat["modules"].get("\\" + top) or stat.get("design", {})
by_type = mod.get("num_cells_by_type", {})
ffs = sum(n for t, n in by_type.items() if t.lstrip("\\") in seq)
area = mod.get("area", 0.0)
print(f"{name:<40} {mod.get('num_cells', 0):>8} {ffs:>11} {area:>14.2f}")
# Hard macros this unit instantiates: "<unit>\t<std-cell area>\t<macro>\t<count>".
with open(sys.argv[5], "a") as out:
    for t, n in sorted(by_type.items()):
        if t.lstrip("\\") in macros:
            out.write(f"{name}\t{area}\t{t.lstrip(chr(92))}\t{n}\n")
PY
done <<< "$units"

# Hard-macro area from the LEF SIZE (informational).
if [ -s "$tmp/macros.tsv" ]; then
	lef_dirs=()
	[ -n "${PDK_ROOT:-}" ] && lef_dirs+=("$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/lef")
	# The PDK the Liberty file comes from (.../libs.ref/<lib>/lib/<file>).
	lef_dirs+=("$(dirname "$(dirname "$(dirname "$LIBERTY")")")/sg13cmos5l_sram/lef")
	echo
	python3 - "$tmp/macros.tsv" "${lef_dirs[@]}" <<'PY'
import collections, os, re, sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
dirs = [d for d in sys.argv[2:] if os.path.isdir(d)]
def lef_size(macro):
    for d in dirs:
        p = os.path.join(d, macro + ".lef")
        if os.path.isfile(p):
            m = re.search(r"^\s*MACRO\s+" + re.escape(macro) + r"\b.*?^\s*SIZE\s+([\d.]+)\s+BY\s+([\d.]+)",
                          open(p).read(), re.S | re.M)
            if m:
                return float(m.group(1)), float(m.group(2)), d
    return None
units = collections.OrderedDict()
for unit, area, macro, n in rows:
    units.setdefault(unit, [float(area), []])[1].append((macro, int(n)))
sizes = {m: lef_size(m) for _, _, m, _ in rows}
if not all(sizes.values()):
    missing = sorted(m for m, s in sizes.items() if not s)
    print("macro area: PDK not available (no LEF for " + ", ".join(missing) + ")")
    sys.exit(0)
print("Hard macros (LEF SIZE from " + ", ".join(sorted({s[2] for s in sizes.values()})) + ")")
print(f"{'unit':<40} {'macro':<36} {'n':>3} {'macro um^2':>11} {'total um^2':>12}")
for unit, (area, macros) in units.items():
    m_area = 0.0
    for macro, n in macros:
        w, h, _ = sizes[macro]
        m_area += n * w * h
        print(f"{unit:<40} {macro:<36} {n:>3} {n * w * h:>11.2f}")
    print(f"{unit:<40} {'total incl. macros':<36} {'':>3} {m_area:>11.2f} {area + m_area:>12.2f}")
PY
fi

[ "$fails" -eq 0 ]
