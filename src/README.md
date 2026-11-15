# src/

RTL for the Protocol Emulator (SystemVerilog; main_ss is Verilog-2005
as its spec requires). Single clock domain, all flops
async reset to 0.

One folder per block, `src/<block>/`, with the file list `src/<block>/<block>.f`
(paths relative to the repo root, `#` comments). The scripts in `scripts/` find
the blocks through these lists. `tt_um_protocol_emulator_placeholder.v` is the
current Tiny Tapeout top (listed in `info.yaml`).

## src/host_link/

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

## src/sys_ctrl/

System control (`pe_sys_ctrl`): registers 0x1C00–0x1C05, shared prescaler,
main-core and sub-core run control, IRQ, doorbell and WAIT vector. Bus target
that never waits. Spec:
`docs/Implementation_spec/System_control_implementation_specification_v1.2.pdf`
(v1.2, D-SYS-7..10 confirmed by the owner on 15 Nov 2026; WAIT / EVENTS bit 15 = `bs_valid_i` from
`main_ss`, A-CHG-7).

| File | Contents | Flops |
|---|---|---|
| `sys_ctrl.sv` | Top level, wiring only; `wready`/`rready` tied 1 | 0 |
| `sys_ctrl_psc.sv` | Prescaler: `cnt[11:0]`, registered ticks `tick[2:0]` | 15 |
| `sys_ctrl_ctrl.sv` | Write decode, sub-core strobes (`run_q`, `halt_q`), `mc_run`, `irq`, `db` | 11 |
| `sys_ctrl_rd.sv` | Read offset `off_q`, read mux, WAIT vector | 4 |
| `sys_ctrl.f` | Filelist | |

The interconnect decodes addr[15:4] and raises `req_i` only for this block
(AS-1); the block uses addr[3:0] and wdata[7:0] only.

## src/main_ss/

Main-core subsystem: main core, the single SRAM macro with its port logic, and
the CRC + bit-stream unit (0x1C10-0x1C19). Spec:
`docs/Implementation_spec/Main_Subsystem_implementation_specification.pdf`
(v1.1, D-MC-1..17), where the block is `pe_mcu_subsys` and the modules carry a
`pe_` prefix. Verilog-2005, `default_nettype none`.

| File | Contents | Flops |
|---|---|---|
| `main_ss.v` | Top: host request classification, target ready/rdata (`rsel_q`), CRC-block access mux | 1 |
| `mc_core.v` | Core: control (`pc`, `irv`, pending load), decode, ALU, register file r1-r7, bus master | 130 |
| `icg.v` | Clock gate per register-file row (`sg13cmos5l_lgcp_1` with `PE_USE_CELLS`, else behavioural latch + AND) | 0 |
| `sram_if.v` | SRAM port priority (host > data > fetch) and the `RM_IHPSG13_1P_512x16_c2_bm_bist` instance | 0 |
| `crc_bs.v` | CRC LFSR, bit-stream stuffing / destuffing / NRZI / packer, OUT, read register | 147 |
| `main_ss.f` | Filelist (the SRAM macro model is in the PDK, not listed) | |

The interconnect raises `t_req_i` for 0x0000-0x01FF and 0x1C10-0x1C1F (one
select, D-MC-8). Simulation needs the PDK SRAM model
(`libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_512x16_c2_bm_bist.v` and
`RM_IHPSG13_1P_core_behavioral_bm_bist.v`, `-DFUNCTIONAL`). The block checks
in `scripts/` use the black box in `verification/stubs/` instead.

## Status

- host_link and sys_ctrl not yet simulated. Both synthesize in Yosys 0.9:
  host_link 48 flops, sys_ctrl 30 flops.
- main_ss: 278 flops + 7 clock-gate latches + SRAM macro; about 37.6k um^2
  in `scripts/block_area.sh` (spec estimate 33.6k, budget 32k). A directed
  Icarus test (not yet in the repo) matches the Appendix B scenarios T1-T13
  clock by clock and the CRC-8/16/32/5 check values. Not yet compared with
  mc11.py.
- No SystemVerilog interfaces are used; all ports are plain `input`/`output`.
