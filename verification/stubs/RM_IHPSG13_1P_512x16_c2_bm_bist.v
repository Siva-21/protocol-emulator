// -----------------------------------------------------------------------------
// Black-box stub of the IHP SRAM macro RM_IHPSG13_1P_512x16_c2_bm_bist
// (ports only). Read by scripts/check_rtl_frontend.sh, scripts/lint_rtl.sh and
// scripts/block_area.sh so that blocks instantiating the macro
// (main_ss / sram_if) can be checked without the PDK (CI).
//
// Not for simulation or hardening: those use the PDK model,
// libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_512x16_c2_bm_bist.v
// (+ RM_IHPSG13_1P_core_behavioral_bm_bist.v, with -DFUNCTIONAL).
// -----------------------------------------------------------------------------

`default_nettype none

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
(* blackbox *)
module RM_IHPSG13_1P_512x16_c2_bm_bist (
  input  wire        A_CLK,
  input  wire        A_MEN,
  input  wire        A_WEN,
  input  wire        A_REN,
  input  wire [8:0]  A_ADDR,
  input  wire [15:0] A_DIN,
  input  wire        A_DLY,
  output wire [15:0] A_DOUT,
  input  wire [15:0] A_BM,
  input  wire        A_BIST_CLK,
  input  wire        A_BIST_EN,
  input  wire        A_BIST_MEN,
  input  wire        A_BIST_WEN,
  input  wire        A_BIST_REN,
  input  wire [8:0]  A_BIST_ADDR,
  input  wire [15:0] A_BIST_DIN,
  input  wire [15:0] A_BIST_BM
);
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
