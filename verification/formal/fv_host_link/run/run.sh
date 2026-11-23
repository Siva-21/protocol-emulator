#!/usr/bin/env bash
# run.sh: run the host_link formal job (inside pe-verif).
#   verification/formal/fv_host_link/run/run.sh          all tasks (prove, bmc, cover)
#   verification/formal/fv_host_link/run/run.sh prove    one task
# Results in run/: fv_host_link_<task>/ (status, logfile.txt, engine_0/trace.vcd)
# and fv_host_link[_<task>].log. A failing property goes to ../issues/ (see README there).
set -euo pipefail
cd "$(dirname "$0")"                       # sby resolves [files] against cwd
task="${1:-}"
sby -f --prefix fv_host_link ../src/fv_host_link.sby ${task} 2>&1 \
  | tee "fv_host_link${task:+_$task}.log"
