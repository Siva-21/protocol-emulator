#!/usr/bin/env bash
# run.sh: run the sysbus formal job (inside pe-verif).
#   verification/formal/fv_sysbus/run/run.sh          all tasks (prove, bmc, cover)
#   verification/formal/fv_sysbus/run/run.sh prove    one task
# Results in run/: fv_sysbus_<task>/ (status, logfile.txt, engine_0/trace.vcd)
# and fv_sysbus[_<task>].log. A failing property goes to ../issues/ (see README there).
set -euo pipefail
cd "$(dirname "$0")"                       # sby resolves [files] against cwd
task="${1:-}"
sby -f --prefix fv_sysbus ../src/fv_sysbus.sby ${task} 2>&1 \
  | tee "fv_sysbus${task:+_$task}.log"
