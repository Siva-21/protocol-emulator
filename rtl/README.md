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

## sys_ctrl/

System control (`pe_sys_ctrl`): registers 0x1C00–0x1C05, shared prescaler,
main-core and sub-core run control, IRQ, doorbell and WAIT vector. Bus target
that never waits. Spec:
`docs/Implementation_spec/System_control_implementation_specification.pdf`
(v1.1, D-SYS-7..10 as written).

| File | Contents | Flops |
|---|---|---|
| `sys_ctrl.sv` | Top level, wiring only; `wready`/`rready` tied 1 | 0 |
| `sys_ctrl_psc.sv` | Prescaler: `cnt[11:0]`, registered ticks `tick[2:0]` | 15 |
| `sys_ctrl_ctrl.sv` | Write decode, sub-core strobes (`run_q`, `halt_q`), `mc_run`, `irq`, `db` | 11 |
| `sys_ctrl_rd.sv` | Read offset `off_q`, read mux, WAIT vector | 4 |
| `sys_ctrl.f` | Filelist | |

The interconnect decodes addr[15:4] and raises `req_i` only for this block
(AS-1); the block uses addr[3:0] and wdata[7:0] only.

## Status

- Not yet simulated. Both blocks synthesize in Yosys 0.9: host_link 48 flops,
  sys_ctrl 30 flops.
- No SystemVerilog interfaces are used; all ports are plain `input`/`output`.
