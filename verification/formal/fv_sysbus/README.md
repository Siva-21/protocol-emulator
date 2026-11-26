# fv_sysbus: formal verification of sysbus

Formal (SymbiYosys) proofs for `src/sysbus/` (the system bus: two masters, host
link first and main core second, a host-only target port to main_ss, and a
shared chip bus ("bus targets" in the testplan) with one-hot selects to
sys_ctrl, the four sub-cores and the pin layer; unmapped addresses are accepted
and read 0). Spec:
`docs/Implementation_spec/Sysbus_Implementation_Specification.pdf` (v1.0, 15 Nov 2026).

**Status (2026-11-24, RTL `e811967`):** properties coded from the approved testplan
([testplan/sysbus_fv_testplan.md](testplan/sysbus_fv_testplan.md)): 29 asserts,
16 assumes, 42 covers.

- prove (abc pdr): all 29 asserts proved unbounded. The log shows 26 outputs, because
  yosys merges asserts with identical logic (2505, 2512 and 2513 are merged).
- bmc (smtbmc bitwuzla, depth 40): no failing assert.
- cover (smtbmc bitwuzla, depth 40): all 42 covers reached (steps 2 to 13).

## Layout

```
fv_sysbus/
  README.md                 this file
  src/                      tracked sources
    fv_sysbus.sby           sby job: tasks prove / bmc / cover
    fv_sysbus.sv            top: clock/reset assumptions, instantiates the
                            files below, bound to sysbus (ports = RTL ports)
    fv_sysbus_host_link_if.sv  host link (master 0, h_*) properties only
    fv_sysbus_main_ss_if.sv    main_ss properties only: m_* (master 1) and
                               t_* (host-only target)
    fv_sysbus_targets_if.sv    sys_ctrl, sub-cores, pin layer properties only
    fv_sysbus_e2e.sv        properties across the ports: routing, arbitration,
                            data integrity
  run/                      run here; only run.sh (and .gitkeep) are tracked
    run.sh                  wrapper: sby + log
  issues/                   one folder per issue found, traces tracked
    README.md               convention
  testplan/
    sysbus_fv_testplan.md   property list, assumptions, spec mapping
```

## Run

Inside `pe-verif`, **from `run/`**: sby resolves the `[files]` paths against the
current directory, and `--prefix` keeps its work folders in `run/` (without it
they would be created in `src/`, next to the `.sby`).

```bash
cd verification/formal/fv_sysbus/run
sby -f --prefix fv_sysbus ../src/fv_sysbus.sby          # all tasks
sby -f --prefix fv_sysbus ../src/fv_sysbus.sby prove    # one task
```

`run/run.sh [task]` does the same and tees a log.

## Results

All in `run/`, git-ignored, replaced by the next `sby -f`:

- `fv_sysbus_<task>/status` (`PASS` / `FAIL`), `fv_sysbus_<task>/logfile.txt`;
- failing assertion: prove (abc pdr `--keep-going`) writes one
  `fv_sysbus_prove/engine_0/trace_<n>.vcd` per failing output, bmc writes
  `engine_0/trace.vcd` (the log names the property label, `file:line` and step);
  cover: `engine_0/trace<N>.vcd`;
- `fv_sysbus/status.sqlite`: sby's status database;
- `fv_sysbus[_<task>].log`: the wrapper's log.

A failing property is copied to `issues/<issue_name>/` (short snake_case name of
the issue) with its trace, a `.gtkw` save file and `notes.md` ([issues/README.md](issues/README.md)). Viewing
traces: [docs/WORKFLOWS.md](../../../docs/WORKFLOWS.md#formal-trace-debug).
