# fv_host_link: formal verification of host_link

Formal (SymbiYosys) proofs for `src/host_link/` (SPI target that turns one 40-bit
frame into one 16-bit bus access as master 0). Spec:
`docs/Implementation_spec/Host_link_implementation_spec.pdf` (frozen 7 Nov 2026).

**Status (2026-11-22, RTL `e811967`):** properties coded from the approved testplan
([testplan/host_link_fv_testplan.md](testplan/host_link_fv_testplan.md)): 24 asserts,
13 assumes, 15 covers.

- prove (abc pdr): 23 of 24 asserts proved unbounded; 1111 fails (MISO changes at
  the read-window opening, tracked in JIRA, see
  [issues/miso_changes_before_sck_fall/](issues/miso_changes_before_sck_fall/)).
- cover (smtbmc, depth 600): all 15 covers reached (steps 7 to 569).
- 1221/1222 are over-constraints (`_oc`), to be checked as asserts on the bus
  target side.

## Layout

```
fv_host_link/
  README.md                 this file
  src/                      tracked sources
    fv_host_link.sby        sby job: tasks prove / bmc / cover
    fv_host_link.sv         top: clock/reset assumptions, instantiates the files
                            below, bound to host_link (ports = RTL ports)
    fv_host_link_host_if.sv     host (SPI) interface properties only
    fv_host_link_sysbus_if.sv   system bus interface properties only
    fv_host_link_e2e.sv         properties across both interfaces, data integrity
  run/                      run here; only run.sh (and .gitkeep) are tracked
    run.sh                  wrapper: sby + log
  issues/                   one folder per issue found, traces tracked
    README.md               convention
  testplan/
    host_link_fv_testplan.md   property list, assumptions, spec mapping
```

## Run

Inside `pe-verif`, **from `run/`**: sby resolves the `[files]` paths against the
current directory, and `--prefix` keeps its work folders in `run/` (without it
they would be created in `src/`, next to the `.sby`).

```bash
cd verification/formal/fv_host_link/run
sby -f --prefix fv_host_link ../src/fv_host_link.sby          # all tasks
sby -f --prefix fv_host_link ../src/fv_host_link.sby prove    # one task
```

`run/run.sh [task]` does the same and tees a log.

## Results

All in `run/`, git-ignored, replaced by the next `sby -f`:

- `fv_host_link_<task>/status` (`PASS` / `FAIL`), `fv_host_link_<task>/logfile.txt`;
- failing assertion: prove (abc pdr `--keep-going`) writes one
  `fv_host_link_prove/engine_0/trace_<n>.vcd` per failing output, bmc writes
  `engine_0/trace.vcd` (the log names the property label, `file:line` and step);
  cover: `engine_0/trace<N>.vcd`;
- `fv_host_link/status.sqlite`: sby's status database;
- `fv_host_link[_<task>].log`: the wrapper's log.

A failing property is copied to `issues/<issue_name>/` (short snake_case name of
the issue) with its trace, a `.gtkw` save file and `notes.md` ([issues/README.md](issues/README.md)). Viewing
traces: [docs/WORKFLOWS.md](../../../docs/WORKFLOWS.md#formal-trace-debug).
