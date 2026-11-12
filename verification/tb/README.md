# Unit tests (cocotb)

Per-block cocotb testbenches, one directory per block:

```
tb/<block>/
  Makefile          cocotb makefile; sources from src/<block>/<block>.f, TOPLEVEL = <block>
  test_<block>.py   cocotb tests
```

- Simulator: Verilator by default (same as `test/`), Icarus via `SIM=icarus`.
- The top-level Tiny Tapeout test stays in `test/` (template layout); this
  directory is for the blocks under `src/<block>/`.
- Output (`sim_build/`, `results.xml`, waveforms) is git-ignored.
