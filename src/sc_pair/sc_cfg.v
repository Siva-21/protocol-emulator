// -----------------------------------------------------------------------------
// sc_cfg
//
// The 34 configuration words of architecture §4.11 (window 0x10-0x31), as
// latches behind one clock gate per word (spec §4.0, §4.1, D-SC-3, O-11).
// en[k] is the write enable decoded in W (sc_win); the word is open in the
// first half of W+1 and takes d = xr_q.
//
// cfg_o holds word k (offset 0x10 + k) at [16k +: 16]; bits above the word's
// width read 0. Widths (447 latches, 445 on a partner, which has no
// SEQ_CFG.SPLIT latches, D-SC-14):
//
//   k  off  word        bits      k  off  word        bits
//   0  10   T1_PER      16        13 1D   EVU0        13   (EVU0-EVU3)
//   1  11   T1_CMP      16        17 21   OUT0        11   (OUT0-OUT5)
//   2  12   T1_CTL      12        23 27   EXT_CFG     16
//   3  13   T1_FRAC      8        24 28   SEQ_CFG     14   (12 on a partner)
//   4  14   T2_PER      16        25 29   DISP_CFG     7
//   5  15   T2_CMP      16        26 2A   PRE0        10   (PRE0, PRE1)
//   6  16   T2_CTL      12        28 2C   PATO0       15   (PATO0-PATO5)
//   7  17   CNT_PRE     16
//   8  18   CNT_CTL      9
//   9  19   MATCH_VAL   16
//   10 1A   MATCH_MASK  16
//   11 1B   SA_CFG      14
//   12 1C   SB_CFG      15
// -----------------------------------------------------------------------------

`default_nettype none

module sc_cfg #(
  parameter IS_MASTER = 0
) (
  input  wire           clk,
  input  wire           rst_n,
  input  wire [33:0]    en,
  input  wire [15:0]    d,
  output wire [543:0]   cfg_o
);

  function integer cw;
    input integer k;
    begin
      case (k)
        2, 6:                    cw = 12;
        3:                       cw = 8;
        8:                       cw = 9;
        11:                      cw = 14;
        12:                      cw = 15;
        13, 14, 15, 16:          cw = 13;
        17, 18, 19, 20, 21, 22:  cw = 11;
        24:                      cw = 14;
        25:                      cw = 7;
        26, 27:                  cw = 10;
        28, 29, 30, 31, 32, 33:  cw = 15;
        default:                 cw = 16;
      endcase
    end
  endfunction

  genvar k;
  generate
    for (k = 0; k < 34; k = k + 1) begin : g_w
      localparam integer W = cw(k);
      wire gclk;
      icg u_icg (.clk(clk), .en(en[k]), .gclk(gclk));
      if (k == 24 && IS_MASTER == 0) begin : g_seq_p
        // partner SEQ_CFG: ENTRY [4:0], BP_EN/BP_STATE/SBIT_SRC [13:7]
        wire [4:0] lo;
        wire [6:0] hi;
        lword #(.W(5)) u_lo (.rst_n(rst_n), .g(gclk), .d(d[4:0]),  .q(lo));
        lword #(.W(7)) u_hi (.rst_n(rst_n), .g(gclk), .d(d[13:7]), .q(hi));
        assign cfg_o[16*k +: 16] = {2'b00, hi, 2'b00, lo};
      end else if (W < 16) begin : g_part
        wire [W-1:0] q;
        lword #(.W(W)) u_l (.rst_n(rst_n), .g(gclk), .d(d[W-1:0]), .q(q));
        assign cfg_o[16*k +: 16] = {{(16-W){1'b0}}, q};
      end else begin : g_full
        lword #(.W(16)) u_l (.rst_n(rst_n), .g(gclk), .d(d), .q(cfg_o[16*k +: 16]));
      end
    end
  endgenerate

endmodule
