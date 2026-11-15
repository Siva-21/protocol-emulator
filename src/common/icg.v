// -----------------------------------------------------------------------------
// icg
//
// Clock gate shared by the blocks (main_ss spec §2.2, §5.6, D-MC-14: one per
// register-file row; sub-core spec §7, D-CG-1: one per configuration word,
// program half-row and FIFO entry). With PE_USE_CELLS defined it instantiates sg13cmos5l_lgcp_1
// (Liberty: clock_gating_integrated_cell "latch_posedge"); otherwise it is the
// behavioural equivalent: a latch transparent while clk is low, ANDed with clk.
//
// en must settle before the rising edge of clk.
// -----------------------------------------------------------------------------

`default_nettype none

module icg (
  input  wire clk,
  input  wire en,
  output wire gclk
);

`ifdef PE_USE_CELLS
  sg13cmos5l_lgcp_1 u_cg (.CLK(clk), .GATE(en), .GCLK(gclk));
`else
  reg en_l;
  /* verilator lint_off LATCH */
  always @(clk or en) if (!clk) en_l = en;   // latch, transparent while clk is low
  /* verilator lint_on LATCH */
  assign gclk = clk & en_l;
`endif

endmodule
