#!/usr/bin/env bash
# Lint every RTL unit with Verilator:
#   verilator --lint-only -Wall --top-module <top> <file>...
# Units: each src/<block>/<block>.f (top module <block>) plus the Tiny Tapeout
# top from info.yaml. Prints PASS/FAIL per unit (first warnings on failure);
# exits 1 if any unit fails.
#
#   scripts/lint_rtl.sh                      (env: VERILATOR=verilator)
set -euo pipefail

VERILATOR=${VERILATOR:-verilator}
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
	# shellcheck disable=SC2086  # file list is intentionally word-split
	if "$VERILATOR" --lint-only -Wall --top-module "$top" $files > "$log" 2>&1; then
		echo "PASS  $name"
	else
		echo "FAIL  $name"
		grep -m 8 -E "^%(Warning|Error)" "$log" | sed 's/^/      /' || tail -n 8 "$log" | sed 's/^/      /'
		fails=$((fails + 1))
	fi
done <<< "$units"

echo "$(wc -l <<< "$units") unit(s), $fails failed"
[ "$fails" -eq 0 ]
