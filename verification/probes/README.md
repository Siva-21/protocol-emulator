# Hardening probes

Thin Tiny Tapeout tops that wrap one block, to harden that block on its own
before it is integrated into the real top:

```
probes/tt_um_<block>_probe.v    module tt_um_<block>_probe, standard TT ports,
                                instantiates <block>
```

Run (inside `pe-verif`, repo root):

```bash
scripts/harden_local.sh --probe <block>
```

`harden_local.sh` copies the repo to a temp directory, puts the probe top first
in a temporary `info.yaml` with the files from `src/<block>/<block>.f`, and runs
harden, submission and precheck there (the gate-level test is skipped: the
`test/` bench drives the real top). The repo itself is not changed.

Probe rules: plain Verilog (no SystemVerilog interfaces, as for every TT top),
and every TT input must be used, since LibreLane's disconnected-pin check
stays enabled.
