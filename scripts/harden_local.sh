#!/usr/bin/env bash
# Local Tiny Tapeout flow, run INSIDE the pe-verif container (repo mounted under
# /foss/designs). Mirrors the TT IHP CI (gds -> precheck -> gl_test) with the
# image's LibreLane 3.1.0.dev4 and the CI PDK prefetched into the image
# (ihp-sg13 @ 89d42ee6...), so it runs offline once the venvs exist.
#
#   scripts/harden_local.sh                 # harden the real top (info.yaml)
#   scripts/harden_local.sh --probe <block> # harden verification/probes/tt_um_<block>_probe.v
#                                           # around src/<block>/<block>.f, in a temp copy
#
# Stages: tt-support-tools -> venvs -> user-config -> harden -> submission ->
# precheck -> gl-test. Stops at the first failing stage; always prints a summary.
#
# Env:
#   TT_TOOLS_REF     tt-support-tools ref (default: main, as CI's gds action)
#   CI_IHP_PDK_HASH  CI PDK version under $PDK_ROOT_CI (default: the image's)
#   PDK_ROOT_CI      CI PDK root (set by the image: /foss/pdks-ci)
#
# Python: tt_tool.py needs a few packages the image lacks (gdstk, chevron,
# configupdater, python-frontmatter). They come from .venv-tt (tt/requirements.txt),
# appended LAST to PYTHONPATH so the image's own packages -- LibreLane, ciel,
# numpy -- always win. precheck.py uses .venv-precheck, put FIRST on PYTHONPATH so
# its CI pins (numpy 1.26 + gdstk 0.9.52) are used, as in CI.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT_TOOLS_URL=https://github.com/TinyTapeout/tt-support-tools
TT_TOOLS_REF=${TT_TOOLS_REF:-main}
PDK=ihp-sg13cmos5l
CI_IHP_PDK_HASH=${CI_IHP_PDK_HASH:-89d42ee6d2fd9b50b86a1aada6fee6673c3e6008}
PDK_ROOT_CI=${PDK_ROOT_CI:-/foss/pdks-ci}
PDK_VERSION_DIR=$PDK_ROOT_CI/ciel/ihp-sg13/versions/$CI_IHP_PDK_HASH
VENV_TT=$REPO/.venv-tt
VENV_PRECHECK=$REPO/.venv-precheck

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

PROBE=""
while [ $# -gt 0 ]; do
	case $1 in
		--probe) PROBE=${2:?--probe needs a block name}; shift 2 ;;
		-h|--help) usage 0 ;;
		*) echo "unknown argument: $1" >&2; usage 2 ;;
	esac
done

[ -d "$PDK_VERSION_DIR/$PDK" ] || { echo "ERROR: CI PDK not found at $PDK_VERSION_DIR (run inside pe-verif)" >&2; exit 2; }
command -v openroad-librelane > /dev/null || { echo "ERROR: openroad-librelane not found (run inside pe-verif)" >&2; exit 2; }

# --- summary bookkeeping ------------------------------------------------------
STAGES=(); STATUS=(); SECS=()
TT_COMMIT="-"; WORK=$REPO; LOGS=""
summary() {
	local i m="$WORK/runs/wokwi/final/metrics.json"
	echo
	echo "================ harden_local summary ================"
	[ -n "$PROBE" ] && echo "probe:            tt_um_${PROBE}_probe (run dir $WORK)"
	echo "tt-support-tools: $TT_COMMIT ($TT_TOOLS_REF)"
	echo "PDK:              $PDK @ $CI_IHP_PDK_HASH"
	for i in "${!STAGES[@]}"; do
		printf '  %-12s %-5s %6ss\n' "${STAGES[$i]}" "${STATUS[$i]}" "${SECS[$i]}"
	done
	if [ -f "$m" ]; then
		python3 - "$m" "$WORK" <<-'PY'
		import glob, json, re, sys
		m = json.load(open(sys.argv[1]))
		ffs = "-"
		stats = sorted(glob.glob(f"{sys.argv[2]}/runs/wokwi/*-yosys-synthesis/reports/stat.json"))
		if stats:
		    s = json.load(open(stats[-1]))
		    mod = s.get("design") or next(iter(s["modules"].values()))
		    ffs = sum(n for t, n in mod.get("num_cells_by_type", {}).items()
		              if re.search(r"_(s?df|dl)[a-z]*_\d+$", t))
		def g(k, f="{}"):
		    v = m.get(k)
		    return "-" if v is None else f.format(v)
		print(f"cells (std):      {g('design__instance__count__stdcell')} (synthesis flip-flops: {ffs})")
		print(f"utilisation:      {g('design__instance__utilization__stdcell', '{:.4%}')}")
		print(f"worst setup/hold: {g('timing__setup__ws', '{:+.3f}')} / {g('timing__hold__ws', '{:+.3f}')} ns")
		print(f"DRC/LVS:          magic {g('magic__drc_error__count')}, route {g('route__drc_errors')}, LVS {g('design__lvs_error__count')}")
		PY
	fi
	[ -f "$WORK/tt/precheck/reports/results.md" ] && \
		echo "precheck:         $(grep -c '✅' "$WORK/tt/precheck/reports/results.md") passed, $(grep -c '❌' "$WORK/tt/precheck/reports/results.md") failed ($WORK/tt/precheck/reports/results.md)"
	echo "GDS:              $(ls "$WORK"/tt_submission/*.gds 2>/dev/null || echo '-')"
	echo "logs:             $LOGS"
	echo "======================================================"
}
trap summary EXIT

# run_stage <name> <command...>: run, log, time; record PASS/FAIL; stop on FAIL.
run_stage() {
	local name=$1 t0 rc=0; shift
	echo "== $name"
	t0=$(date +%s)
	# Background subshell + wait: `set -e` stays active inside the stage
	# (it is ignored for anything called from an `||` list).
	( "$@" ) > "$LOGS/$name.log" 2>&1 &
	wait $! || rc=$?
	STAGES+=("$name"); SECS+=($(( $(date +%s) - t0 )))
	if [ "$rc" -eq 0 ]; then
		STATUS+=(PASS)
	else
		STATUS+=(FAIL)
		echo "   FAIL (exit $rc), last lines of $LOGS/$name.log:"
		tail -n 15 "$LOGS/$name.log" | sed 's/^/   | /'
		exit 1
	fi
}

# --- stage functions ----------------------------------------------------------
stage_tt_tools() {
	if [ -d "$REPO/tt/.git" ]; then
		git -C "$REPO/tt" fetch --depth 1 origin "$TT_TOOLS_REF"
		git -C "$REPO/tt" checkout -q --detach FETCH_HEAD
	else
		rm -rf "$REPO/tt"
		git clone -q --depth 1 --branch "$TT_TOOLS_REF" "$TT_TOOLS_URL" "$REPO/tt" 2>/dev/null || {
			# a commit hash is not a valid --branch: fetch it explicitly
			git init -q "$REPO/tt"
			git -C "$REPO/tt" remote add origin "$TT_TOOLS_URL"
			git -C "$REPO/tt" fetch --depth 1 origin "$TT_TOOLS_REF"
			git -C "$REPO/tt" checkout -q --detach FETCH_HEAD
		}
	fi
	git -C "$REPO/tt" rev-parse HEAD
}

stage_venvs() {
	local v req
	for v in "$VENV_TT:$REPO/tt/requirements.txt" "$VENV_PRECHECK:$REPO/tt/precheck/requirements.txt"; do
		req=${v#*:}; v=${v%%:*}
		[ -x "$v/bin/python" ] || python3 -m venv --system-site-packages "$v"
		"$v/bin/pip" install -q --disable-pip-version-check -r "$req"
	done
}

site() { echo "$1/lib/python3.$(python3 -c 'import sys; print(sys.version_info.minor)')/site-packages"; }

# Environment for tt_tool.py / LibreLane: CI PDK store, LibreLane-matched OpenROAD.
tt_env() {
	cd "$WORK"
	export PDK PDK_ROOT=$PDK_ROOT_CI
	export PATH=/foss/tools/openroad-librelane/bin:$PATH
	export PYTHONPATH=${PYTHONPATH:-}:$(site "$VENV_TT")
}
stage_user_config() { (tt_env; ./tt/tt_tool.py --create-user-config --pdk "$PDK"); }
stage_harden()      { (tt_env; ./tt/tt_tool.py --harden --pdk "$PDK" --no-docker); }
stage_submission()  { (tt_env; ./tt/tt_tool.py --create-tt-submission --pdk "$PDK"); }

stage_precheck() {
	local gds
	gds=$(ls "$WORK"/tt_submission/*.gds)
	(
		cd "$WORK/tt/precheck"
		# shellcheck disable=SC1091
		. "$VENV_PRECHECK/bin/activate"
		export PYTHONPATH=$(site "$VENV_PRECHECK"):${PYTHONPATH:-}
		export PDK PDK_ROOT=$PDK_VERSION_DIR
		python precheck.py --gds "$gds" --tech "$PDK"   # absolute path, as CI
	)
}

stage_gl_test() {
	cp "$WORK"/tt_submission/*.v "$WORK/test/gate_level_netlist.v"   # IHP: nl netlist, as CI
	(
		cd "$WORK/test"
		rm -f results.xml
		make -B GATES=yes PDK="$PDK" PDK_ROOT="$PDK_VERSION_DIR"
		python3 -m cocotb_tools.check_results results.xml
	)
}

# --- main ---------------------------------------------------------------------
LOGS=$REPO/runs/harden_local/logs
mkdir -p "$LOGS"
run_stage tt-tools stage_tt_tools
TT_COMMIT=$(git -C "$REPO/tt" rev-parse --short=12 HEAD)
echo "   tt-support-tools $TT_TOOLS_REF @ $TT_COMMIT"
run_stage venvs stage_venvs

if [ -n "$PROBE" ]; then
	top=tt_um_${PROBE}_probe
	flist=$REPO/src/$PROBE/$PROBE.f
	probe_v=$REPO/verification/probes/$top.v
	[ -f "$flist" ] || { echo "ERROR: $flist not found" >&2; exit 2; }
	[ -f "$probe_v" ] || { echo "ERROR: $probe_v not found" >&2; exit 2; }
	WORK=$(mktemp -d "${TMPDIR:-/tmp}/harden_probe_${PROBE}.XXXXXX")
	echo "== probe run in $WORK"
	tar -C "$REPO" --exclude=./.git --exclude=./runs --exclude=./tt --exclude='./.venv*' \
		--exclude=./tt_submission -cf - . | tar -C "$WORK" -xf -
	tar -C "$REPO" --exclude=./precheck/reports -cf - tt | tar -C "$WORK" -xf -
	# TT wants every source in src/: copy the probe top there, list it FIRST (tt_tool's
	# port check reads only the first file), then the block's .f entries.
	cp "$probe_v" "$WORK/src/$top.v"
	python3 - "$WORK/info.yaml" "$top" "$flist" <<-'PY'
	import os, sys, yaml
	path, top, flist = sys.argv[1:]
	files = [f"{top}.v"]
	for line in open(flist):
	    line = line.split("#", 1)[0].strip()
	    if line:
	        files.append(os.path.relpath(line, "src"))
	info = yaml.safe_load(open(path))
	info["project"]["top_module"] = top
	info["project"]["title"] = f"{info['project'].get('title', '')} ({top})"
	info["project"]["source_files"] = files
	yaml.safe_dump(info, open(path, "w"), sort_keys=False)
	PY
	# --harden records the git remote and commit: give the temp copy a throwaway repo.
	git -C "$WORK" init -q
	git -C "$WORK" remote add origin "$(git -C "$REPO" remote get-url origin 2>/dev/null || echo https://example.invalid/probe.git)"
	git -C "$WORK" add -A > /dev/null
	git -C "$WORK" -c user.name=harden_local -c user.email=harden_local@localhost commit -q -m "probe $top (temp)"
	LOGS=$WORK/runs/harden_local/logs
	mkdir -p "$LOGS"
fi

run_stage user-config stage_user_config
run_stage harden stage_harden
run_stage submission stage_submission
run_stage precheck stage_precheck
if [ -n "$PROBE" ]; then
	echo "== gl-test skipped (test/ bench targets the real top, not the probe)"
	STAGES+=(gl-test); STATUS+=(SKIP); SECS+=(0)
else
	run_stage gl-test stage_gl_test
fi
