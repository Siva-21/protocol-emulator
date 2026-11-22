# miso_changes_before_sck_fall

MISO takes R[7] at E3 after the 24th SCK rise, while SCK is still high, not at
E3 after an SCK fall.

| File | Content |
|---|---|
| `trace.vcd` | counterexample (`engine_0/trace_14.vcd`), 1 step = 10 time units |
| `trace.yw` | Yosys witness of the same trace, for replay |
| `sby_prove.log` | sby log of the run: setup, the CEX for output 14 and its replay (abc progress lines removed) |
| `ast_1111.gtkw` | GTKWave view: `gtkwave trace.vcd ast_1111.gtkw` (from this folder) |

| Field | Content |
|---|---|
| Property | 1111, `ast_1111_miso_change_at_e3_after_fall` in `src/fv_host_link_host_if.sv`: `(!spi_csn_i && $changed(spi_miso_o)) -> $past(fv_sck_fall, 3)` |
| sby task / step | `prove`, abc `pdr --keep-going`, output 14, CEX in frame 200, replay fails at step 271 (VCD time 2700 is the change). Run of 2026-11-22, with the 1101/1103/1104/1107 rewrites and the 1221/1222 over-constraints. Same case as the first failure (run of 2026-11-20, frame 145, change at step 267). RTL at commit `e811967` |
| Root cause | see below |
| Fault | spec / RTL mismatch (open). No functional impact on a mode 0 host |
| Resolution | open, tracked in JIRA: spec clarification (relax 1111 for the window-opening change) or RTL change (`miso_en` at the first DATA fall) |

## Root cause

`spi_miso_o = sr[15] & miso_en` (`host_link_dp.sv`). `miso_en` turns on when the
phase enters DATA, which happens at E3 after the 24th rise, not after a fall.

| Step | SCK pin | sck_s2 | rise_en | bc | ph | miso_en | sr | MISO | Note |
|---|---|---|---|---|---|---|---|---|---|
| 262 | 0 | 1 | 0 | 15 | CMD | 0 | 0x8000 | 0 | last fall before the failure |
| 267 | 1 | 0 | 0 | 15 | CMD | 0 | 0x8000 | 0 | 24th rise at the pin; host samples bit 24 = 0 |
| 269 | 1 | 1 | 1 | 15 | CMD | 0 | 0x8000 | 0 | E2: rise seen |
| 270 | 1 | 1 | 0 | 0 | DATA | 1 | 0x8000 | **1** | E3: ph = DATA, miso_en = 1, MISO = R[7] while SCK is high |
| 271 | | | | | | | | | check fails: no fall 3 clocks earlier |

## Impact

- Mode 0 host samples on rises only: bit 24 is 0 at rise 24, R[7] is valid at
  rise 25 (the first DATA fall does not shift, bc = 0, T2 footnote). Hold after
  rise 24 is 2-3 clocks, the same as T5 gives. No functional impact.
- Spec text mismatch: HL-08 / Impl spec §3 "MISO is 0 outside the read-data
  bytes", T5 "MISO changes at E3 after a fall", T2 figure shows R[7] from the
  bit-25 period. The T2 footnote matches the RTL.
- Not checked by this trace: the end of the window (MISO back to 0 after bit 40).
