// -----------------------------------------------------------------------------
// sc_win
//
// Bus window of one sub-core (spec §3, §4.1, §4.14; architecture §6.2).
// Every access with req_i = 1 is accepted in its clock W; effects land at the
// edge ending W. xr_q is the registered read data (rdata_o, valid in W+1) and,
// in the clock after a write, the D input of every latch (D-SC-3).
//
//   0x00 CTRL     W  [0] RUN [1] HALT [2] STEP [3] SOFT_RESET [4] FLUSH_A
//                    [5] FLUSH_B [6] CLR_ERR   (ctrl, decoded in W)
//   0x01 STATUS   R  [4:0] state [5] halted_eff [6] bp_hit [9:7] NTF1-3
//                    [12:10] FA_EMPTY FB_OVR FA_OVR
//   0x02 NTF ack  W  [2:0]; a same-clock set wins (D-SC-12)
//   0x03 MAILBOX  RW [3:0]
//   0x04/0x05     W  FIFO A push (sc_fifo_a)
//   0x06          R  FIFO B head data, pop at the edge (sc_fifo_b)
//   0x07 LEVELS   R  [3:0] FIFO A count [7:4] FIFO B count [8] FIFO B head tag
//   0x08          R  [0] entry [4:1] sticky [5] ext_st [6] FIFO A head tag
//   0x09-0x0E     R  cnt, t1_cnt[15:0], t2_cnt, sa_sr, sb_sr, FIFO A head data
//   0x0F          R  [3:0] evr_e [4] t1p [5] t1c [6] t2p [7] t2c [8] err
//   0x10-0x31     W  configuration latches, only if halted_eff in W
//   0x40-0x5F     W  program half-rows, only if halted_eff in W (and the
//                    master's halted_eff for a lent partner row)
//   others        R 0, writes ignored
//
// STATUS and LEVELS use the bit positions of architecture §6.2; the debug
// words 0x08 and 0x0F use the concatenations of spec §4.1 ({a, b} = a above b).
//
// Flops: xr_q 16, err 3, ntf 3, mb 4, sig 2, evr_err 1 = 29.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_win #(
  parameter IS_MASTER = 0
) (
  input  wire        clk,
  input  wire        rst_n,
  // bus target
  input  wire        req_i,
  input  wire        dir_i,
  input  wire [6:0]  addr_i,
  input  wire [15:0] wdata_i,
  output reg  [15:0] xr_q,
  // decoded access
  output wire        wr,
  output wire        rd,
  output wire [6:0]  ctrl,
  output wire [33:0] cfg_en,
  output wire [31:0] row_en,
  // run state
  input  wire        halted_eff,
  /* verilator lint_off UNUSEDSIGNAL */
  input  wire        m_heff_i,      // partner only
  input  wire [1:0]  m_split_i,     // partner only
  /* verilator lint_on UNUSEDSIGNAL */
  // flag sources
  input  wire        fa_empty_set,
  input  wire        fb_ovr_set,
  input  wire        fa_ovr_set,
  input  wire [2:0]  u_ntf,         // micro-ops NTF1-NTF3
  input  wire [1:0]  u_sig,         // micro-ops {SIG1, SIG0}
  output reg  [2:0]  err,           // {FA_OVR, FB_OVR, FA_EMPTY}
  output reg  [2:0]  ntf,
  output reg  [3:0]  mb,
  output reg  [1:0]  sig,
  output reg         evr_err,
  // read sources
  input  wire [4:0]  state,
  input  wire        entry,
  input  wire        bp_hit,
  input  wire [16:0] fb_head,
  input  wire [1:0]  fb_cnt,
  input  wire [2:0]  fa_cnt,
  input  wire [16:0] fa_head,
  input  wire        ext_st,
  input  wire [3:0]  sticky,
  input  wire [15:0] cnt,
  input  wire [15:0] t1_cnt,
  input  wire [15:0] t2_cnt,
  input  wire [15:0] sa_sr,
  input  wire [15:0] sb_sr,
  input  wire [3:0]  evr_e,
  input  wire        evr_t1p,
  input  wire        evr_t1c,
  input  wire        evr_t2p,
  input  wire        evr_t2c
);

  assign wr = req_i & dir_i;
  assign rd = req_i & ~dir_i;

  wire [15:0] wd = wdata_i;

  assign ctrl = (wr && addr_i == 7'h00) ? wd[6:0] : 7'd0;
  wire   srst = ctrl[3];

  // ---- read mux
  reg [15:0] rdm;
  always @(*) begin
    case (addr_i)
      7'h01:   rdm = {3'b000, err, ntf, bp_hit, halted_eff, state};
      7'h03:   rdm = {12'd0, mb};
      7'h06:   rdm = fb_head[15:0];
      7'h07:   rdm = {7'd0, fb_head[16], 2'b00, fb_cnt, 1'b0, fa_cnt};
      7'h08:   rdm = {9'd0, fa_head[16], ext_st, sticky, entry};
      7'h09:   rdm = cnt;
      7'h0A:   rdm = t1_cnt;
      7'h0B:   rdm = t2_cnt;
      7'h0C:   rdm = sa_sr;
      7'h0D:   rdm = sb_sr;
      7'h0E:   rdm = fa_head[15:0];
      7'h0F:   rdm = {7'd0, evr_err, evr_t2c, evr_t2p, evr_t1c, evr_t1p, evr_e};
      default: rdm = 16'd0;
    endcase
  end

  // ---- latch write enables (D-SC-3, O-11)
  genvar k;
  generate
    for (k = 0; k < 34; k = k + 1) begin : g_cfg_en
      assign cfg_en[k] = wr & (addr_i == 7'h10 + k) & halted_eff;
    end
    for (k = 0; k < 32; k = k + 1) begin : g_row_en
      wire lent;
      if (IS_MASTER != 0) begin : g_m
        assign lent = 1'b0;
      end else begin : g_p
        // lent to the master: 24/8 and row < 8, or 32/0 (SPLIT code 3 = 16/16)
        assign lent = ((m_split_i == 2'd1) && (k < 16)) | (m_split_i == 2'd2);
      end
      wire lent_ok = ~lent | m_heff_i;
      assign row_en[k] = wr & (addr_i == 7'h40 + k) & halted_eff & lent_ok;
    end
  endgenerate

  // ---- flags (§4.14)
  wire [2:0] ntf_clr = (wr && addr_i == 7'h02) ? wd[2:0] : 3'd0;
  wire [2:0] err_set = {fa_ovr_set, fb_ovr_set, fa_empty_set};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      xr_q    <= 16'd0;
      err     <= 3'd0;
      ntf     <= 3'd0;
      mb      <= 4'd0;
      sig     <= 2'd0;
      evr_err <= 1'b0;
    end else begin
      xr_q    <= wr ? wd : rdm;
      err     <= (err & ~{3{ctrl[6]}}) | err_set;
      ntf     <= (ntf & ~ntf_clr) | u_ntf;
      mb      <= (wr && addr_i == 7'h03) ? wd[3:0] : mb;
      sig     <= srst ? 2'd0 : u_sig;
      evr_err <= srst ? 1'b0 : |err_set;
    end
  end

endmodule
