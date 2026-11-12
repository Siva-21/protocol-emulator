#!/usr/bin/env bash
# Read every RTL unit with Yosys's built-in Verilog frontend exactly as LibreLane
# does (USE_SLANG off, the Tiny Tapeout default) and check the hierarchy:
#   read_verilog -defer -noautowire -sv <file>...; hierarchy -check -top <top>
# Units: each src/<block>/<block>.f (top module <block>) plus the Tiny Tapeout
# top from info.yaml. Prints PASS/FAIL per unit; exits 1 if any unit fails.
#
#   scripts/check_rtl_frontend.sh            (env: YOSYS=yosys)
set -euo pipefail

YOSYS=${YOSYS:-yosys}
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

log=$(mktemp); trap 'rm -f "$log"' EXIT
units=$(list_units)
fails=0
while IFS=$'\t' read -r name top files; do
	miss=$(missing_files "$files")
	if [ -n "$miss" ]; then
		echo "FAIL  $name  (missing:$miss)"; fails=$((fails + 1)); continue
	fi
	cmd=""
	for f in $files; do cmd+="read_verilog -defer -noautowire -sv $f; "; done
	cmd+="hierarchy -check -top $top"
	if "$YOSYS" -q -p "$cmd" > "$log" 2>&1; then
		# With -defer, modules are elaborated at hierarchy time under the
		# `default_nettype in effect at the END of reading. If that is `wire`
		# (e.g. the last file resets it), an unresolved name such as an
		# interface member (bus.clk) only WARNS "is implicitly declared" and
		# becomes a dangling wire -- the design is silently wrong. Treat that
		# warning like the error it is under `default_nettype none.
		if grep -q "is implicitly declared" "$log"; then
			echo "FAIL  $name  (implicitly declared identifiers)"
			grep -m 5 "is implicitly declared" "$log" | sed 's/^/      /'
			fails=$((fails + 1))
		else
			echo "PASS  $name"
		fi
	else
		echo "FAIL  $name"
		grep -m 5 -E "ERROR|Error" "$log" | sed 's/^/      /' || tail -n 5 "$log" | sed 's/^/      /'
		fails=$((fails + 1))
	fi
done <<< "$units"

echo "$(wc -l <<< "$units") unit(s), $fails failed"
[ "$fails" -eq 0 ]
