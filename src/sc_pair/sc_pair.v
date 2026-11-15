// -----------------------------------------------------------------------------
// sc_pair
//
// Sub-core pair (spec pe_sc_pair, D-SC-1; architecture §4.10): u_m is the
// pair master (SC0 or SC2, IS_MASTER = 1), u_p its partner (SC1 or SC3).
// The pair shares the elastic program store: the master's 32-bit 2:1 picks
// the partner's lo_o / hi_o for states 16-31, and the partner's read halves
// follow the master's state in the 24/8 and 32/0 splits. No logic here.
//
// Every other port is passed through with a [1:0] index: [0] = master,
// [1] = partner (q_o[5:0] master, q_o[11:6] partner, and so on).
// PAIR (0 = SC0 + SC1, 1 = SC2 + SC3) only names the instance.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_pair #(
  /* verilator lint_off UNUSEDPARAM */
  parameter PAIR     = 0,
  /* verilator lint_on UNUSEDPARAM */
  parameter FA_DEPTH = 4,
  parameter NPAT     = 5
) (
  input  wire        clk,
  input  wire        rst_n,
  // bus target (req one-hot from the interconnect)
  input  wire [1:0]  req_i,
  input  wire        dir_i,
  input  wire [6:0]  addr_i,
  input  wire [15:0] wdata_i,
  output wire [1:0]  wready_o,
  output wire [1:0]  rready_o,
  output wire [31:0] rdata_o,
  // pins
  input  wire [15:0] in_i,
  input  wire [15:0] in_r_i,
  output wire [11:0] q_o,
  output wire [11:0] qoe_o,
  output wire [15:0] tap_o,         // [7:0] master taps; [15:8] partner, 0
  output wire [1:0]  tap_oe_o,
  // sys_ctrl
  input  wire [1:0]  run_i,
  input  wire [1:0]  halt_i,
  input  wire [2:0]  tick_i,
  output wire [1:0]  fa_space_o,
  output wire [1:0]  fb_ne_o,
  output wire [1:0]  ntf_o,
  output wire [1:0]  halted_o,
  output wire [1:0]  err_o,
  // SIG lines
  output wire [3:0]  sig_o,
  input  wire [7:0]  sig_i
);

  wire [31:0] p_lo, p_hi;
  wire [1:0]  m_split;
  wire [2:0]  m_state;
  wire        m_heff;

  /* verilator lint_off PINCONNECTEMPTY */
  subcore #(.IS_MASTER(1), .FA_DEPTH(FA_DEPTH), .NPAT(NPAT)) u_m (
    .clk(clk), .rst_n(rst_n),
    .req_i(req_i[0]), .dir_i(dir_i), .addr_i(addr_i), .wdata_i(wdata_i),
    .wready_o(wready_o[0]), .rready_o(rready_o[0]), .rdata_o(rdata_o[15:0]),
    .in_i(in_i), .in_r_i(in_r_i), .q_o(q_o[5:0]), .qoe_o(qoe_o[5:0]),
    .tap_o(tap_o[7:0]), .tap_oe_o(tap_oe_o[0]),
    .run_i(run_i[0]), .halt_i(halt_i[0]), .tick_i(tick_i),
    .fa_space_o(fa_space_o[0]), .fb_ne_o(fb_ne_o[0]), .ntf_o(ntf_o[0]),
    .halted_o(halted_o[0]), .err_o(err_o[0]),
    .sig_o(sig_o[1:0]), .sig_i(sig_i),
    .p_lo_i(p_lo), .p_hi_i(p_hi), .split_o(m_split), .mstate_o(m_state), .mheff_o(m_heff),
    .m_split_i(2'd0), .m_state_i(3'd0), .m_heff_i(1'b0), .lo_o(), .hi_o()
  );

  subcore #(.IS_MASTER(0), .FA_DEPTH(FA_DEPTH), .NPAT(NPAT)) u_p (
    .clk(clk), .rst_n(rst_n),
    .req_i(req_i[1]), .dir_i(dir_i), .addr_i(addr_i), .wdata_i(wdata_i),
    .wready_o(wready_o[1]), .rready_o(rready_o[1]), .rdata_o(rdata_o[31:16]),
    .in_i(in_i), .in_r_i(in_r_i), .q_o(q_o[11:6]), .qoe_o(qoe_o[11:6]),
    .tap_o(tap_o[15:8]), .tap_oe_o(tap_oe_o[1]),
    .run_i(run_i[1]), .halt_i(halt_i[1]), .tick_i(tick_i),
    .fa_space_o(fa_space_o[1]), .fb_ne_o(fb_ne_o[1]), .ntf_o(ntf_o[1]),
    .halted_o(halted_o[1]), .err_o(err_o[1]),
    .sig_o(sig_o[3:2]), .sig_i(sig_i),
    .p_lo_i(32'd0), .p_hi_i(32'd0), .split_o(), .mstate_o(), .mheff_o(),
    .m_split_i(m_split), .m_state_i(m_state), .m_heff_i(m_heff), .lo_o(p_lo), .hi_o(p_hi)
  );
  /* verilator lint_on PINCONNECTEMPTY */

endmodule
