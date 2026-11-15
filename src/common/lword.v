// -----------------------------------------------------------------------------
// lword
//
// One latch word (sub-core spec §4.0, pin-layer spec §4.0): W latches, transparent while g
// is high, cleared by rst_n. g is a gated clock from icg, so a word is open in
// the first half of the clock after its write was accepted, with d = xr_q
// (D-SC-3). With PE_USE_CELLS defined each bit is sg13cmos5l_dlhrq_1;
// otherwise it is the behavioural equivalent.
// -----------------------------------------------------------------------------

`default_nettype none

module lword #(
  parameter W = 16
) (
  input  wire         rst_n,
  input  wire         g,
  input  wire [W-1:0] d,
  output wire [W-1:0] q
);

`ifdef PE_USE_CELLS
  genvar i;
  generate
    for (i = 0; i < W; i = i + 1) begin : g_bit
      sg13cmos5l_dlhrq_1 u_l (.D(d[i]), .GATE(g), .RESET_B(rst_n), .Q(q[i]));
    end
  endgenerate
`else
  reg [W-1:0] l;
  /* verilator lint_off LATCH */
  always @(*) begin
    if (!rst_n)
      l = {W{1'b0}};
    else if (g)
      l = d;
  end
  /* verilator lint_on LATCH */
  assign q = l;
`endif

endmodule

