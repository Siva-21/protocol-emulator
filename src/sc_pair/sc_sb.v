// -----------------------------------------------------------------------------
// sc_sb
//
// SB, the RX shifter (spec §4.9, architecture §4.6, D-SC-7, D-SC-16):
// N = 1-16 bits, 1/2/4/8 lanes sampled from IN_R[PIN ..] (rotated), MSB- or
// LSB-first, stream mode pushes every N bits into FIFO B. Priority ARM > PUSH
// > STOP > STEP / capture event. Words are right-aligned.
//
// One shared left shifter (D-SC-7) does the LSB-first insert, shl(smp, n - w),
// and the SB.PUSH alignment, rev16(shl(rev16(sb_sr), n - sb_bc)).
// The bit count saturates at N (D-SC-16): an SB.PUSH after an overlong
// SB.STEP run pushes the last N bits unshifted.
//
// SB_CFG: [3:0] N-1 [4] MSB [6:5] LANES [9:7] EV [10] STREAM [14:11] PIN.
// Flops: sr 16, bc 5, armed, done, last = 24.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_sb (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        srst,
  input  wire        u_arm,
  input  wire        u_step,
  input  wire        u_push,
  input  wire        u_stop,
  input  wire [14:0] cfg,
  input  wire [3:0]  evr_e,
  input  wire        evr_t1p,
  input  wire        evr_t1c,
  input  wire        evr_t2p,
  input  wire        evr_t2c,
  input  wire [15:0] in_r_i,
  output reg  [15:0] sb_sr,
  output reg         sb_done,
  output reg         sb_last,
  output reg         sb_cap,
  output reg         req0,          // FIFO B request 0 (SB word)
  output reg  [15:0] req0_d
);

  reg [4:0] sb_bc;
  reg       sb_armed;

  wire [4:0] n      = {1'b0, cfg[3:0]} + 5'd1;
  wire       msb    = cfg[4];
  wire [3:0] w      = 4'd1 << cfg[6:5];
  wire [7:0] ev_v   = {evr_e, evr_t2c, evr_t2p, evr_t1c, evr_t1p};
  wire       cap    = ev_v[cfg[9:7]];
  wire       stream = cfg[10];
  wire [3:0] pin    = cfg[14:11];

  function [15:0] rev16;
    input [15:0] x;
    integer i;
    begin
      for (i = 0; i < 16; i = i + 1) rev16[i] = x[15-i];
    end
  endfunction

  // sample: IN_R rotated right by PIN, lanes 0..w-1
  /* verilator lint_off UNUSEDSIGNAL */
  wire [31:0] in2   = {in_r_i, in_r_i} >> pin;
  /* verilator lint_on UNUSEDSIGNAL */
  wire [15:0] lmask = (16'd1 << w) - 16'd1;
  wire [15:0] smp   = in2[15:0] & lmask;

  // the shared shifter
  wire [4:0]  amt    = u_push ? (n - sb_bc) : (n - {1'b0, w});
  wire [15:0] sh_in  = u_push ? rev16(sb_sr) : smp;
  wire [15:0] sh_out = sh_in << amt;

  wire [15:0] nmask = 16'hFFFF >> (5'd16 - n);
  wire [15:0] sr_st = msb ? (((sb_sr << w) | smp) & nmask) : ((sb_sr >> w) | sh_out);
  wire [4:0]  bc_w  = sb_bc + {1'b0, w};
  wire [4:0]  bc_st = (bc_w > n) ? n : bc_w;

  reg [15:0] sr_n;
  reg [4:0]  bc_n;
  reg        armed_n, done_n, last_n;

  always @(*) begin
    sr_n    = sb_sr;
    bc_n    = sb_bc;
    armed_n = sb_armed;
    done_n  = stream ? 1'b0 : sb_done;
    last_n  = sb_last;
    sb_cap  = 1'b0;
    req0    = 1'b0;
    req0_d  = 16'd0;
    if (u_arm) begin
      bc_n    = 5'd0;
      sr_n    = 16'd0;
      armed_n = 1'b1;
      done_n  = 1'b0;
    end else if (u_push) begin
      if (sb_bc != 5'd0) begin
        req0   = 1'b1;
        req0_d = msb ? sb_sr : rev16(sh_out);
      end
      bc_n   = 5'd0;
      sr_n   = 16'd0;
      done_n = 1'b0;
    end else if (u_stop) begin
      armed_n = 1'b0;
    end else if (u_step | (cap & sb_armed)) begin
      sr_n   = sr_st;
      bc_n   = bc_st;
      last_n = smp[0];
      sb_cap = 1'b1;
      if (bc_st >= n) begin
        done_n = 1'b1;
        if (stream) begin
          req0   = 1'b1;
          req0_d = sr_st;
          bc_n   = 5'd0;
          sr_n   = 16'd0;
        end else begin
          armed_n = 1'b0;
        end
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sb_sr    <= 16'd0;
      sb_bc    <= 5'd0;
      sb_armed <= 1'b0;
      sb_done  <= 1'b0;
      sb_last  <= 1'b0;
    end else if (srst) begin
      sb_sr    <= 16'd0;
      sb_bc    <= 5'd0;
      sb_armed <= 1'b0;
      sb_done  <= 1'b0;
      sb_last  <= 1'b0;
    end else begin
      sb_sr    <= sr_n;
      sb_bc    <= bc_n;
      sb_armed <= armed_n;
      sb_done  <= done_n;
      sb_last  <= last_n;
    end
  end

endmodule
