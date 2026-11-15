# src/

RTL for the Protocol Emulator (SystemVerilog; main_ss, sc_pair, pin_layer and
sysbus are Verilog-2005 as their specs require). Single clock domain, all flops
async reset to 0, except the pin-layer input chains (no reset, D-PL-1).

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
| `sram_if.v` | SRAM port priority (host > data > fetch) and the `RM_IHPSG13_1P_512x16_c2_bm_bist` instance | 0 |
| `crc_bs.v` | CRC LFSR, bit-stream stuffing / destuffing / NRZI / packer, OUT, read register | 147 |
| `main_ss.f` | Filelist (the SRAM macro model is in the PDK, not listed) | |

The interconnect raises `t_req_i` for 0x0000-0x01FF and 0x1C10-0x1C1F (one
select, D-MC-8). Simulation needs the PDK SRAM model
(`libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_512x16_c2_bm_bist.v` and
`RM_IHPSG13_1P_core_behavioral_bm_bist.v`, `-DFUNCTIONAL`). The block checks
in `scripts/` use the black box in `verification/stubs/` instead. The
register-file clock gates use `src/common/icg.v`.

## src/common/

Modules shared by several blocks; each block's `.f` lists the files it uses.
Not a block of its own (no `.f`).

| File | Contents |
|---|---|
| `icg.v` | Clock gate (`sg13cmos5l_lgcp_1` with `PE_USE_CELLS`, else behavioural latch + AND); main_ss register-file rows, sc_pair configuration words, program half-rows and FIFO entries, pin_layer latch words and GPIO |
| `lword.v` | Latch word, transparent while its gated clock is high, cleared by `rst_n` (`sg13cmos5l_dlhrq_1` with `PE_USE_CELLS`, else behavioural); sc_pair and pin_layer configuration / program latches |

## src/sc_pair/

Sub-core pair: SC0 + SC1 or SC2 + SC3 sharing the elastic program store.
Spec: `docs/Implementation_spec/Subcore_Implementation_Specification.pdf`
(v1.0, 15 Nov 2026), where the modules are `pe_sc_pair` / `pe_subcore` and the
clock gate is `pe_icg`. D-SC-16 confirmed by the owner on 15 Nov 2026.
Verilog-2005, `default_nettype none`. `sc_pair` instantiates the master `u_m`
(`IS_MASTER = 1`) and the partner `u_p`; other ports are passed through with a
`[1:0]` index (`[0]` = master).

| File | Contents | Flops |
|---|---|---|
| `sc_pair.v` | Pair top, wiring only | 0 |
| `subcore.v` | One sub-core, wiring only; `wready`/`rready` tied 1 | 0 |
| `sc_win.v` | Bus window: decode, read mux, `xr_q` (read data and latch write hold), error / NTF / MAILBOX / SIG flags, latch write enables | 29 |
| `sc_cfg.v` | 34 configuration words, 447 latches (445 on a partner) behind 34 clock gates | 0 |
| `sc_bank.v` | Program bank, 16 x 32 latches behind 32 clock gates, two 8:1 read halves, pair select | 0 |
| `sc_seq.v` | State, entry, run control, breakpoint, STEP; conditions, preemption, DISP, micro-op strobes and pin codes; matcher and EXT | 10 |
| `sc_evu.v` | One event unit (x4): event register bit and sticky bit | 2 |
| `sc_tmr.v` | Timer T1 (17-bit count, fraction) / T2 (16-bit) and its two event-register bits | 30 / 20 |
| `sc_cnt.v` | 16-bit counter | 16 |
| `sc_sa.v` | SA (TX shifter), lanes, underrun hold | 31 |
| `sc_sb.v` | SB (RX shifter), one shared shifter (D-SC-7) | 24 |
| `sc_fifo_a.v` | FIFO A, 4 x 17, clock-gated entries, one pop per clock | 73 |
| `sc_fifo_b.v` | FIFO B, 2 x 17, clock-gated entries, three writers, FBNEW | 38 |
| `sc_out.v` | Outputs O0-O5 (pin codes, patterns, SA / AUX following, NPART), SA taps on the master | 36 + 9 |
| `sc_pair.f` | Filelist (includes `src/common/icg.v`, `src/common/lword.v`) | |

Per sub-core: 959 latches (957 on a partner), 324 flops (315), 72 clock gates.
The reserved SEQ_CFG.SPLIT code 3 reads as 16/16, as in sc11.py.

## src/pin_layer/

Pin layer: 43 sources onto the 15 output pads (uo1-uo7, uio0-uio7) through
combinational selects, and the 16 input pads into IN / IN_R through 16
five-flop chains with loopback and glitch filter; registers 0x1800-0x181F.
Spec: `docs/Implementation_spec/Pin_layer_Implementation_Specification.pdf`
(v1.0, 15 Nov 2026), where the block is `pe_pin_layer`. D-PL-1 to D-PL-4,
D-PL-9 and D-PL-10 confirmed by the owner on 15 Nov 2026. Verilog-2005,
`default_nettype none`. `uo_out[0]` (host link MISO) is not driven here.

| File | Contents | Flops |
|---|---|---|
| `pin_layer.v` | Top: bus window and `xr_q`, GPIO_OUT / GPIO_OE (one clock gate each), PAD_CFG x15 / FILT_UI / FILT_UIO / LOOPBACK latches (18 clock gates), pad slices, input chains | 46 |
| `pin_layer_pad.v` | One pad slice (x15): 8:1 per code group, 8:1 by group, drive-enable select on uio pads, MODE logic | 0 |
| `pin_layer_in.v` | One input chain (x16): loopback mux, `s1`, filter `y` (= IN) with counter `c`, `in_r`; no reset (D-PL-1) | 5 |
| `pin_layer.f` | Filelist (includes `src/common/icg.v`, `src/common/lword.v`) | |

126 flops (80 of them without reset), 168 latches (Yosys removes the 7 unused
MODE[0] latches of the uo pads), 20 clock gates.

## src/sysbus/

System bus: host link (master 0) and main core (master 1) to the seven bus
targets and the unmapped space. Spec:
`docs/Implementation_spec/Sysbus_Implementation_Specification.pdf` (v1.0,
15 Nov 2026), where the block is `pe_sysbus`. The D-BUS-3 correction and
D-BUS-5 to D-BUS-9 confirmed by the owner on 15 Nov 2026. Verilog-2005,
`default_nettype none`.

| File | Contents | Flops |
|---|---|---|
| `sysbus.v` | Host range decode and ready, host-only path to main_ss (`t_*`), chip-bus master select (host first), 16-bit chip decode, read-select flops `ts_q` / `hm_q`, read mux | 5 |
| `sysbus.f` | Filelist | |

Host addresses 0x0000-0x01FF and 0x1C10-0x1C1F go only to the main_ss target
port and may wait (CRC busy); everything else is on the shared chip bus, where
the host wins and the core is held one clock. Sub-cores 0x1000 + 0x80*n,
pin layer 0x1800-0x181F, sys_ctrl 0x1C00-0x1C0F get a one-hot `req` and the
full broadcast `c_addr`; unmapped addresses are accepted and read 0. Sideband
wiring (SIG, WAIT, strobes, ticks, IRQ, IN/IN_R, pad sources) is not here
(D-BUS-1).

## Status

- host_link and sys_ctrl not yet simulated. Both synthesize in Yosys 0.9:
  host_link 48 flops, sys_ctrl 30 flops.
- main_ss: 278 flops + 7 clock-gate latches + SRAM macro; about 37.6k um^2
  in `scripts/block_area.sh` (spec estimate 33.6k, budget 32k). A directed
  Icarus test (not yet in the repo) matches the Appendix B scenarios T1-T13
  clock by clock and the CRC-8/16/32/5 check values. Not yet compared with
  mc11.py.
- sc_pair: 639 flops + 1916 latches + 144 clock gates for the pair; about
  175.4k um^2 in `scripts/block_area.sh`, 87.7k per sub-core (spec estimate
  80.8k, budget 81.6k). Co-simulated against the spec equations (sc_eq.py,
  which cosim_sc.py checks against sc11.py): 200 random runs x 3000 clocks x
  4 sub-cores, every flop and latch equal (20 runs also with the IHP cell
  models). A directed Icarus test matches the spec Appendix A waveforms T1-T6
  clock by clock. The testbenches are not yet in the repo.
- pin_layer: about 27.1k um^2 in `scripts/block_area.sh` (spec estimate
  26.7k, budget 26.3k). A directed Icarus test (not yet in the repo) matches
  the spec Appendix A waveforms T1-T5 clock by clock (T1 together with
  sc_pair), and passes the exhaustive output-select (64 codes x 4 modes),
  loopback, filter latency and register checks, behavioural and with the IHP
  cell models. Not yet compared with pl_eq.py / pe.py (not available here).
- sysbus: 5 flops, about 2.5k um^2 in `scripts/block_area.sh` (spec
  estimate 2.7k). A directed Icarus test (not yet in the repo) matches the spec
  Appendix A waveforms T1-T3, decodes all 65,536 addresses for both masters,
  and runs 200,000 clocks of random two-master traffic against target stubs
  (routing, accept once, read data in W+1, core held while the host is on the
  chip bus, ready independence); it catches the spec's 10 seeded bugs.
- No SystemVerilog interfaces are used; all ports are plain `input`/`output`.
