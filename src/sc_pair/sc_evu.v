// -----------------------------------------------------------------------------
// sc_evu
//
// One event unit Ek (spec §4.5, architecture §4.6): the event register bit
// evr_e and the sticky bit. Edges compare IN with IN_R, so an event is aligned
// with IN_R.
//
//   e        = {cur, cur & !prev, !cur & prev, cur ^ prev}[MODE]
//              & (!QEN | in_i[QPIN] == QLVL)
//   sticky_n = (sticky | evr_e) & !(consume | CLR.Ek)
//
// Flops: 2.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_evu (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        srst,
  input  wire [15:0] in_i,
  input  wire [15:0] in_r_i,
  input  wire [3:0]  pin,
  input  wire [1:0]  mode,         // level / rise / fall / both
  input  wire        qen,
  input  wire [3:0]  qpin,
  input  wire        qlvl,
  input  wire        consume,
  input  wire        clr,
  output reg         evr_e,
  output reg         sticky
);

  wire cur  = in_i[pin];
  wire prev = in_r_i[pin];

  reg e;
  always @(*) begin
    case (mode)
      2'd0:    e = cur;
      2'd1:    e = cur & ~prev;
      2'd2:    e = ~cur & prev;
      default: e = cur ^ prev;
    endcase
  end

  wire e_q = e & (~qen | (in_i[qpin] == qlvl));

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      evr_e  <= 1'b0;
      sticky <= 1'b0;
    end else if (srst) begin
      evr_e  <= 1'b0;
      sticky <= 1'b0;
    end else begin
      evr_e  <= e_q;
      sticky <= (sticky | evr_e) & ~(consume | clr);
    end
  end

endmodule
