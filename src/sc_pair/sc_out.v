// -----------------------------------------------------------------------------
// sc_out
//
// Output stage O0-O5 (spec §4.13, architecture §4.7) and, on a pair master,
// the SA pad taps. Per output: mode (0 VAL, 1 SA, 2 AUX), v, oe and the
// registered q / qoe (one clock from a state's entry to the pad, G-04).
//
//   code 1: VAL v=0 oe=1   2: VAL v=1 oe=1   3: VAL oe=0   4: VAL v=!(q^INV) oe=1
//   code 5: SA oe=1        6: AUX oe=1       7: INIT (SA->SA, AUX->AUX, else VAL),
//                                               v = IDLE, oe = INIT != Z
//   val   = VAL ? v : SA ? sa_lane(LANE) : aux[AUX]
//   aux   = {CLK1, CLK2, sa_lane(0) ^ CLK1, NPART, sb_last, in_r_i[EVU0.PIN],
//            in_r_i[EVU1.PIN], 0}
//   q_n   = val ^ INV;   qoe_n = (SA & OE_LANE) ? sa_lane(LANE + 1) : oe_n
//   NPART, in order k = 0..5: q_n[k] = !(q_n[k^1] ^ INV[k^1]) ^ INV[k]
//   taps_n[j] = sa_lane(j), tap_oe_n = qoe_n[5]   (IS_MASTER only)
//
// OUTk: [0] IDLE [1] INV [4:2] AUX [6:5] INIT (IDLE/SA/AUX/Z) [9:7] LANE
// [10] OE_LANE. SOFT_RESET: mode = INIT, v = IDLE, oe = INIT != Z,
// q = IDLE ^ INV, qoe = oe; taps 0.
// Flops: 6 x 6 = 36, taps 9 (master).
// -----------------------------------------------------------------------------

`default_nettype none

module sc_out #(
  parameter IS_MASTER = 0
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        srst,
  input  wire [17:0] code,
  input  wire [65:0] ocfg,          // OUTk at [11k +: 11]
  input  wire [8:0]  lane,          // sa_lane(0..8)
  input  wire        clk1,
  input  wire        clk2,
  input  wire        sb_last,
  input  wire [15:0] in_r_i,
  input  wire [3:0]  e0_pin,
  input  wire [3:0]  e1_pin,
  output wire [5:0]  q_o,
  output wire [5:0]  qoe_o,
  output wire [7:0]  tap_o,
  output wire        tap_oe_o
);

  localparam [1:0] M_VAL = 2'd0, M_SA = 2'd1, M_AUX = 2'd2;

  reg [11:0] mode;
  reg [5:0]  v, oe, q, qoe;

  reg [11:0] mode_n;
  reg [5:0]  v_n, oe_n, qpre, qfin, qoe_n, npart;

  reg [1:0]  m;
  reg        vv, oo, val, auxv;
  reg [10:0] c;
  reg [7:0]  aux_v;
  integer k;

  always @(*) begin
    for (k = 0; k < 6; k = k + 1) begin
      c  = ocfg[11*k +: 11];
      m  = mode[2*k +: 2];
      vv = v[k];
      oo = oe[k];
      case (code[3*k +: 3])
        3'd1: begin m = M_VAL; vv = 1'b0; oo = 1'b1; end
        3'd2: begin m = M_VAL; vv = 1'b1; oo = 1'b1; end
        3'd3: begin m = M_VAL;            oo = 1'b0; end
        3'd4: begin m = M_VAL; vv = ~(q[k] ^ c[1]); oo = 1'b1; end
        3'd5: begin m = M_SA;             oo = 1'b1; end
        3'd6: begin m = M_AUX;            oo = 1'b1; end
        3'd7: begin
          m  = (c[6:5] == 2'd1) ? M_SA : (c[6:5] == 2'd2) ? M_AUX : M_VAL;
          vv = c[0];
          oo = (c[6:5] != 2'd3);
        end
        default: ;
      endcase
      aux_v = {1'b0, in_r_i[e1_pin], in_r_i[e0_pin], sb_last, 1'b0,
               lane[0] ^ clk1, clk2, clk1};
      auxv  = aux_v[c[4:2]];
      val   = (m == M_VAL) ? vv : (m == M_SA) ? lane[{1'b0, c[9:7]}] : auxv;
      mode_n[2*k +: 2] = m;
      v_n[k]   = vv;
      oe_n[k]  = oo;
      qpre[k]  = val ^ c[1];
      qoe_n[k] = (m == M_SA && c[10]) ? lane[{1'b0, c[9:7]} + 4'd1] : oo;
      npart[k] = (m == M_AUX) && (c[4:2] == 3'd3);
    end
    // NPART: the complement of the partner output, same clock, in index order
    qfin = qpre;
    for (k = 0; k < 6; k = k + 1)
      if (npart[k])
        qfin[k] = ~(qfin[k ^ 1] ^ ocfg[11*(k ^ 1) + 1]) ^ ocfg[11*k + 1];
  end

  // SOFT_RESET values
  reg [11:0] mode_r;
  reg [5:0]  v_r, oe_r, q_r;
  integer i;
  always @(*) begin
    for (i = 0; i < 6; i = i + 1) begin
      mode_r[2*i +: 2] = (ocfg[11*i + 5 +: 2] == 2'd1) ? M_SA :
                         (ocfg[11*i + 5 +: 2] == 2'd2) ? M_AUX : M_VAL;
      v_r[i]  = ocfg[11*i];
      oe_r[i] = (ocfg[11*i + 5 +: 2] != 2'd3);
      q_r[i]  = ocfg[11*i] ^ ocfg[11*i + 1];
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mode <= 12'd0;
      v    <= 6'd0;
      oe   <= 6'd0;
      q    <= 6'd0;
      qoe  <= 6'd0;
    end else if (srst) begin
      mode <= mode_r;
      v    <= v_r;
      oe   <= oe_r;
      q    <= q_r;
      qoe  <= oe_r;
    end else begin
      mode <= mode_n;
      v    <= v_n;
      oe   <= oe_n;
      q    <= qfin;
      qoe  <= qoe_n;
    end
  end

  assign q_o   = q;
  assign qoe_o = qoe;

  generate
    if (IS_MASTER != 0) begin : g_taps
      reg [7:0] taps;
      reg       tap_oe;
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          taps   <= 8'd0;
          tap_oe <= 1'b0;
        end else if (srst) begin
          taps   <= 8'd0;
          tap_oe <= 1'b0;
        end else begin
          taps   <= lane[7:0];
          tap_oe <= qoe_n[5];
        end
      end
      assign tap_o    = taps;
      assign tap_oe_o = tap_oe;
    end else begin : g_no_taps
      assign tap_o    = 8'd0;
      assign tap_oe_o = 1'b0;
    end
  endgenerate

endmodule
