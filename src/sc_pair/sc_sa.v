// -----------------------------------------------------------------------------
// sc_sa
//
// SA, the TX shifter (spec §4.8, architecture §4.6): N = 1-16 bits, 1/2/4/8
// lanes, MSB- or LSB-first, stream reload from FIFO A, skip-first, underrun
// value 0 / 1 / hold. Priority LOAD > STOP > STEP / shift event.
//
//   sa_lane(j) = sa_valid ? (j < w ? (MSB ? sa_sr[n-1-j] : sa_sr[j]) : 0)
//                         : (UDF == hold ? (j < w ? sa_hold[j] : 0) : UDF[0])
//
// lane[8:0] is sa_lane(0..8) (lane 8 for an OE-from-lane on lane 7).
// SA_CFG: [3:0] N-1 [4] MSB [6:5] LANES [9:7] EV (T1P T1C T2P T2C E0-E3)
// [10] STREAM [11] SKIP1 [13:12] UDF (0, 1, hold; 3 reads as 1, P-5).
// Flops: sr 16, bc 4, valid, armed, skip, hold 8 = 31.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_sa (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        srst,
  input  wire        u_load,
  input  wire        u_step,
  input  wire        u_stop,
  input  wire [13:0] cfg,
  input  wire [3:0]  evr_e,
  input  wire        evr_t1p,
  input  wire        evr_t1c,
  input  wire        evr_t2p,
  input  wire        evr_t2c,
  input  wire        fa_ne,
  input  wire [15:0] fa_head,
  output reg  [15:0] sa_sr,
  output reg         sa_valid,
  output wire [8:0]  lane,
  output reg         sa_pop,
  output reg         sa_shifted
);

  reg [3:0] sa_bc;
  reg       sa_armed, sa_skip;
  reg [7:0] sa_hold;

  wire [4:0] n      = {1'b0, cfg[3:0]} + 5'd1;
  wire       msb    = cfg[4];
  wire [3:0] w      = 4'd1 << cfg[6:5];
  wire [7:0] ev_v   = {evr_e, evr_t2c, evr_t2p, evr_t1c, evr_t1p};
  wire       sh     = ev_v[cfg[9:7]];
  wire       stream = cfg[10];
  wire       skip1  = cfg[11];
  wire [1:0] udf    = cfg[13:12];

  // ---- lanes
  /* verilator lint_off UNUSEDSIGNAL */
  wire [15:0] msb_al = sa_sr << (5'd16 - n);        // bit n-1 at bit 15
  /* verilator lint_on UNUSEDSIGNAL */
  wire [7:0]  grp;                                  // the lane group, 0 above w
  genvar j;
  generate
    for (j = 0; j < 8; j = j + 1) begin : g_lane
      wire in_w = (j < w);
      assign grp[j]  = in_w & (msb ? msb_al[15-j] : sa_sr[j]);
      assign lane[j] = sa_valid ? grp[j] : (udf == 2'd2) ? (in_w & sa_hold[j]) : udf[0];
    end
  endgenerate
  assign lane[8] = ~sa_valid & (udf != 2'd2) & udf[0];      // j = 8 >= w

  wire [4:0] bc_w    = {1'b0, sa_bc} + {1'b0, w};
  wire       at_last = sa_valid & (bc_w >= n);

  reg [15:0] sr_n;
  reg [3:0]  bc_n;
  reg        valid_n, armed_n, skip_n;

  always @(*) begin
    sr_n       = sa_sr;
    bc_n       = sa_bc;
    valid_n    = sa_valid;
    armed_n    = sa_armed;
    skip_n     = sa_skip;
    sa_pop     = 1'b0;
    sa_shifted = 1'b0;
    if (u_load) begin
      armed_n = 1'b1;
      valid_n = fa_ne;
      if (fa_ne) begin
        sr_n   = fa_head;
        bc_n   = 4'd0;
        skip_n = skip1;
        sa_pop = 1'b1;
      end
    end else if (u_stop) begin
      valid_n = 1'b0;
      armed_n = 1'b0;
    end else if (u_step | (sh & sa_armed)) begin
      if (sh & sa_skip & ~u_step) begin
        skip_n = 1'b0;
      end else if ((~sa_valid | at_last) & stream & sa_armed) begin
        valid_n = fa_ne;
        if (fa_ne) begin
          sr_n   = fa_head;
          bc_n   = 4'd0;
          skip_n = 1'b0;
          sa_pop = 1'b1;
        end
        sa_shifted = at_last;
      end else if (at_last) begin
        valid_n    = 1'b0;
        armed_n    = 1'b0;
        sa_shifted = 1'b1;
      end else if (sa_valid) begin
        sr_n       = msb ? (sa_sr << w) : (sa_sr >> w);
        bc_n       = bc_w[3:0];
        sa_shifted = 1'b1;
      end
    end
  end

  wire [7:0] hold_n = valid_n ? sa_hold : (sa_valid ? grp : sa_hold);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sa_sr    <= 16'd0;
      sa_bc    <= 4'd0;
      sa_valid <= 1'b0;
      sa_armed <= 1'b0;
      sa_skip  <= 1'b0;
      sa_hold  <= 8'd0;
    end else if (srst) begin
      sa_sr    <= 16'd0;
      sa_bc    <= 4'd0;
      sa_valid <= 1'b0;
      sa_armed <= 1'b0;
      sa_skip  <= 1'b0;
      sa_hold  <= 8'd0;
    end else begin
      sa_sr    <= sr_n;
      sa_bc    <= bc_n;
      sa_valid <= valid_n;
      sa_armed <= armed_n;
      sa_skip  <= skip_n;
      sa_hold  <= hold_n;
    end
  end

endmodule
