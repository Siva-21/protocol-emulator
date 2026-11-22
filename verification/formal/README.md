# Formal (SymbiYosys)

Per-block formal proofs, one directory per block, `fv_<block>/`:

```
formal/fv_<block>/
  README.md                  purpose, how to run, where results go
  src/                       tracked sources
    <block>.sby              SymbiYosys job: RTL from src/<block>/<block>.f + the property files
    <block>_props.sv         properties (assert / assume / cover), bound to <block>
  run/                       run sby here; only run.sh is tracked
    run.sh                   wrapper: sby + log
  issues/                    one folder per failing property: <PROP_ID>_<yyyymmdd>/
                             with trace.vcd, a .gtkw save file and notes.md
  testplan/
    <block>_fv_testplan.md   properties, assumptions, mapping to the spec
```

- Run **from `run/`** with `--prefix`:
  `cd verification/formal/fv_<block>/run && sby -f --prefix <block> ../src/<block>.sby [task]`.
  sby resolves `[files]` against the current directory (so `[files]` lists
  `../../../../src/<block>/<file>` and `../src/<block>_props.sv`), and
  `--prefix` puts the work folders in `run/` (`<block>_<task>/`, plus
  `<block>/status.sqlite`); without it they land in `src/`.
  Template and steps: [docs/WORKFLOWS.md](../../docs/WORKFLOWS.md#formal-with-sby).
- Engines available in `pe-verif`: yices (default), bitwuzla, z3 for
  `smtbmc`; `abc pdr` for unbounded proofs. Read RTL and properties with
  `read_slang` and attach the properties with `bind`.
- Properties stay out of `src/`: the RTL that gets hardened has no formal-only code.
- Git: everything in `run/` except `run.sh` is ignored (work folders, logs,
  traces). `issues/` is tracked, its `*.vcd` / `*.fst` / `*.log` included.
- The older layout `formal/<block>/<block>.sby` (work folders `<block>_<task>/`
  next to it, still git-ignored) is superseded for new blocks.

| Block | Folder | Status |
|---|---|---|
| host_link | [fv_host_link/](fv_host_link/README.md) | set up, testplan written, no properties yet |
