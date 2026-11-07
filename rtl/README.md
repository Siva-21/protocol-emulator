# RTL

SystemVerilog RTL for the Protocol Emulator. Single clock domain, all flops
async reset to 0.

## bus_def/

Shared interfaces used to connect blocks at integration.

| File | Interface | Modports |
|---|---|---|
| `clk_rst_if.sv` | `clk`, `rst_n` (async assert, sync release) | `source`, `sink` |
| `spi_if.sv` | `sck`, `csn`, `mosi`, `miso` (SPI mode 0) | `host`, `target`, `monitor` |
| `sys_bus_if.sv` | `req`, `dir`, `addr`, `wdata`, `wready`, `rready`, `rdata` (`ADDR_W`/`DATA_W`, default 16) | `master`, `slave`, `monitor` |

Use one `sys_bus_if` instance per bus master.

## host_link/

SPI target that turns one 40-bit frame into one 16-bit system bus access
(master 0). Spec: `docs/Implementation_spec/Host_link_implementation_spec.pdf`.

| File | Contents | Flops |
|---|---|---|
| `host_link.sv` | Top level, wiring only; ports `clk_rst_if.sink`, `spi_if.target`, `sys_bus_if.master` | 0 |
| `host_link_sync.sv` | SCK/CS_n/MOSI synchronisers and SCK edge detect | 7 |
| `host_link_ctrl.sv` | Control path: frame FSM (`ph`, `bc`) and bus request FSM (`rw`, `req`, `rpend`) | 9 |
| `host_link_dp.sv` | Datapath: address (`a`) and data (`sr`) shift registers | 32 |
| `host_link.f` | Filelist (bus definitions first) | |

The logic follows the spec §4 equations. Mark `sck_s1`, `csn_s1` and
`mosi_s1` as synchroniser flops in the flow (P3).

## Status

- Not yet simulated. The three submodules synthesize in Yosys 0.9 to 48 flops.
- Yosys 0.9 cannot process interface ports. Use a recent Yosys, Verilator or
  sv2v for the top level.
