// -----------------------------------------------------------------------------
// sc_cnt
//
// 16-bit counter (spec §4.7, architecture §4.6). Priority LDP > LDF > LDB >
// INC/DEC (both together cancel); wrap or saturate. CNT.LDF loads the FIFO A
// head; on an empty FIFO A it keeps the count and raises FA_EMPTY.
//
//   hwev = {E0-E3, T1P, T2P, SA shift, SB capture}[SEL]
//
// CNT_CTL: [0] DEC_EN [3:1] DEC_SEL [4] INC_EN [7:5] INC_SEL [8] WRAP.
// Flops: 16.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_cnt (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        srst,
  input  wire        u_ldp,
  input  wire        u_ldf,
  input  wire        u_ldb,
  input  wire        u_dec,
  input  wire        u_inc,
  input  wire [15:0] pre,
  input  wire [8:0]  ctl,
  input  wire [3:0]  evr_e,
  input  wire        evr_t1p,
  input  wire        evr_t2p,
  input  wire        sa_shifted,
  input  wire        sb_cap,
  input  wire        fa_ne,
  input  wire [15:0] fa_head,
  input  wire [15:0] sb_sr,
  output reg  [15:0] cnt,
  output wire        cnt_zero,
  output wire        burst_end,     // cnt_n == 0 & cnt != 0 (timer GATE)
  output wire        fa_empty_set
);

  wire [7:0] hwev = {sb_cap, sa_shifted, evr_t2p, evr_t1p, evr_e};
  wire dec = u_dec | (ctl[0] & hwev[ctl[3:1]]);
  wire inc = u_inc | (ctl[4] & hwev[ctl[7:5]]);
  wire wrap = ctl[8];

  wire [15:0] cm1 = cnt - 16'd1;
  wire [15:0] cp1 = cnt + 16'd1;

  reg [15:0] cnt_n;
  always @(*) begin
    if (u_ldp)
      cnt_n = pre;
    else if (u_ldf)
      cnt_n = fa_ne ? fa_head : cnt;
    else if (u_ldb)
      cnt_n = sb_sr;
    else if (dec & ~inc)
      cnt_n = (wrap || cnt != 16'd0) ? cm1 : cnt;
    else if (inc & ~dec)
      cnt_n = (wrap || cnt != 16'hFFFF) ? cp1 : cnt;
    else
      cnt_n = cnt;
  end

  assign cnt_zero     = (cnt == 16'd0);
  assign burst_end    = (cnt_n == 16'd0) & ~cnt_zero;
  assign fa_empty_set = u_ldf & ~u_ldp & ~fa_ne;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cnt <= 16'd0;
    else
      cnt <= srst ? 16'd0 : cnt_n;
  end

endmodule
