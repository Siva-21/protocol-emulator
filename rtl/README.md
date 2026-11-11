# RTL

SystemVerilog RTL for the Protocol Emulator. Single clock domain, all flops
async reset to 0.

## host_link/

SPI target that turns one 40-bit frame into one 16-bit system bus access
(master 0). Spec: `docs/Implementation_spec/Host_link_implementation_spec.pdf`.

| File | Contents | Flops |
|---|---|---|
| `host_link.sv` | Top level, wiring only; plain ports `clk`, `rst_n`, `spi_*`, `bus_*` | 0 |
| `host_link_sync.sv` | SCK/CS_n/MOSI synchronisers and SCK edge detect | 7 |
| `host_link_ctrl.sv` | Control path: frame FSM (`ph`, `bc`) and bus request FSM (`rw`, `req`, `rpend`) | 9 |
| `host_link_dp.sv` | Datapath: address (`a`) and data (`sr`) shift registers | 32 |
| `host_link.f` | Filelist | |

The logic follows the spec §4 equations. Mark `sck_s1`, `csn_s1` and
`mosi_s1` as synchroniser flops in the flow (P3).

## Status

- Not yet simulated.
- No SystemVerilog interfaces are used; all ports are plain `input`/`output`.
