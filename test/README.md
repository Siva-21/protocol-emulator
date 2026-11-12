# Top-level test

A cocotb test for the Tiny Tapeout top `tt_um_protocol_emulator_placeholder`
(`tb.v` wraps it; `test.py` drives it). It starts a 50 MHz clock, holds `rst_n`
low for 10 cycles, releases it, waits 5 cycles, then checks that `uo_out` and
`uio_oe` are 0 with no X/Z.

## How to run

```sh
make -B                # RTL, Verilator (default)
make -B SIM=icarus     # RTL, Icarus
make -B GATES=yes      # gate level, Icarus (needs gate_level_netlist.v, see below)
```

For gate level, harden the design and copy the netlist to
`test/gate_level_netlist.v` (for IHP: `runs/wokwi/final/nl/<top>.nl.v`). `PDK_ROOT`
must point at the PDK (`$PDK_ROOT/ihp-sg13cmos5l/...`). Tiny Tapeout's CI does
this automatically and runs `GATES=yes make` with Icarus.

Requirements: `pip install -r requirements.txt` (cocotb 2.1.0); Verilator >= 5.036.

## Waveform

Every run writes `tb.fst` in this directory (`results.xml` holds the test
results). View it with:

```sh
gtkwave tb.fst tb.gtkw
surfer tb.fst
```
