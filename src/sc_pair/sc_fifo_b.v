// -----------------------------------------------------------------------------
// sc_fifo_b
//
// FIFO B, 2 x 17 bits, and FBNEW (spec §4.11, SC-FB, D-SC-4). Writers in the
// order SB word (req0), MARK ({1, 11'b0, state}), CAP (cnt); the j-th request
// present is accepted if fb_cnt + accepted_before < 2 and written to slot
// fb_rp + fb_cnt + accepted_before. Any request not accepted sets FB_OVR.
// fb_lw is the slot written last; FBNEW = fb_mem[fb_lw][15:0], so it survives
// pops and FLUSH_B. A bus read of 0x06 pops. Entries are clock-gated (D-CG-1).
//
// Flops: mem 34, rp 1, cnt 2, lw 1 = 38.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_fifo_b (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        clr,           // CTRL.FLUSH_B | CTRL.SOFT_RESET
  input  wire        rd,
  input  wire [6:0]  addr_i,
  input  wire        req0,
  input  wire [15:0] req0_d,
  input  wire        u_mark,
  input  wire [4:0]  state,
  input  wire        u_cap,
  input  wire [15:0] cnt,
  output reg  [1:0]  fb_cnt,
  output wire [16:0] fb_head,
  output wire [15:0] fbnew,
  output wire        fb_full,
  output wire        fb_ovr_set
);

  reg        fb_rp, fb_lw;
  wire [16:0] m0, m1;

  // ---- accept
  wire [16:0] d0 = {1'b0, req0_d};
  wire [16:0] d1 = {1'b1, 11'd0, state};
  wire [16:0] d2 = {1'b0, cnt};

  wire [1:0] c0 = fb_cnt;
  wire       a0 = req0 & (c0 < 2'd2);
  wire [1:0] c1 = c0 + {1'b0, a0};
  wire       a1 = u_mark & (c1 < 2'd2);
  wire [1:0] c2 = c1 + {1'b0, a1};
  wire       a2 = u_cap & (c2 < 2'd2);
  wire [1:0] acc = {1'b0, a0} + {1'b0, a1} + {1'b0, a2};

  wire s0 = fb_rp ^ c0[0];
  wire s1 = fb_rp ^ c1[0];
  wire s2 = fb_rp ^ c2[0];

  assign fb_ovr_set = (req0 & ~a0) | (u_mark & ~a1) | (u_cap & ~a2);

  wire w0 = (a0 & ~s0) | (a1 & ~s1) | (a2 & ~s2);
  wire w1 = (a0 &  s0) | (a1 &  s1) | (a2 &  s2);
  wire [16:0] wd0 = (a0 & ~s0) ? d0 : (a1 & ~s1) ? d1 : d2;
  wire [16:0] wd1 = (a0 &  s0) ? d0 : (a1 &  s1) ? d1 : d2;

  wire lw_n = a2 ? s2 : a1 ? s1 : a0 ? s0 : fb_lw;

  // ---- storage, one clock gate per entry
  wire g0, g1;
  reg [16:0] e0, e1;
  icg u_icg0 (.clk(clk), .en(w0), .gclk(g0));
  icg u_icg1 (.clk(clk), .en(w1), .gclk(g1));
  always @(posedge g0 or negedge rst_n)
    if (!rst_n) e0 <= 17'd0; else e0 <= wd0;
  always @(posedge g1 or negedge rst_n)
    if (!rst_n) e1 <= 17'd0; else e1 <= wd1;
  assign m0 = e0;
  assign m1 = e1;

  // ---- read side
  wire fb_ne  = (fb_cnt != 2'd0);
  wire fb_pop = rd & (addr_i == 7'h06) & fb_ne;

  assign fb_head = fb_ne ? (fb_rp ? m1 : m0) : 17'd0;
  assign fbnew   = fb_lw ? m1[15:0] : m0[15:0];
  assign fb_full = (fb_cnt == 2'd2);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fb_rp  <= 1'b0;
      fb_lw  <= 1'b0;
      fb_cnt <= 2'd0;
    end else begin
      fb_rp  <= fb_rp ^ fb_pop;
      fb_lw  <= lw_n;
      fb_cnt <= clr ? 2'd0 : fb_cnt + acc - {1'b0, fb_pop};
    end
  end

endmodule
