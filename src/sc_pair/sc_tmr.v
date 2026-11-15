// -----------------------------------------------------------------------------
// sc_tmr
//
// Timer Tk (spec §4.6, architecture §4.6, D-SC-19). T1 (IS_T1 = 1): 17-bit
// count, 8-bit fraction accumulator acc and the extension bit ext; T2: 16-bit
// count, no fraction. Also holds the timer's two event-register bits
// evr_p / evr_c (= mp / mc registered).
//
//   tk      = PSC == 0 ? 1 : tick_i[PSC - 1]
//   mp      = run & tk & (cnt == {0, PER} + ext)
//   mc      = run & tk & (cnt == {0, CMP})
//   restart = Tk.GO | (RST_EN & {E0-E3, other P, other C, 0, 0}[RST_SEL])
//   stop    = Tk.STOP | (ONESHOT & mp) | burst_end
//   CLKk    = wave & !(GATE & counter == 0)
//
// CTL: [3:0] RLD [5:4] PSC [6] RST_EN [9:7] RST_SEL [10] ONESHOT [11] GATE.
// Flops: T1 17 + run + wave + ext + acc 8 + evr 2 = 30; T2 16 + 2 + 2 = 20.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_tmr #(
  parameter IS_T1 = 1
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        srst,
  input  wire [15:0] per,
  input  wire [15:0] cmp,
  input  wire [11:0] ctl,
  /* verilator lint_off UNUSEDSIGNAL */
  input  wire [7:0]  frac,          // T1 only
  /* verilator lint_on UNUSEDSIGNAL */
  input  wire [2:0]  tick_i,
  input  wire        go,
  input  wire        stop_u,
  input  wire [3:0]  evr_e,
  input  wire        oth_p,         // the other timer's registered P / C events
  input  wire        oth_c,
  input  wire        burst_end,     // counter: cnt_n == 0 & cnt != 0
  input  wire        cnt_zero,      // counter == 0
  output reg         evr_p,
  output reg         evr_c,
  output wire        clk_o,         // CLKk (AUX source)
  output wire [15:0] cnt_dbg
);

  localparam W = (IS_T1 != 0) ? 17 : 16;

  reg [W-1:0] cnt;
  reg         run, wave;
  wire        ext;

  wire [3:0] rld     = ctl[3:0];
  wire [1:0] psc     = ctl[5:4];
  wire       rst_en  = ctl[6];
  wire [2:0] rst_sel = ctl[9:7];
  wire       oneshot = ctl[10];
  wire       gate    = ctl[11];

  wire       tk   = (psc == 2'd0) ? 1'b1 : tick_i[psc - 2'd1];
  /* verilator lint_off UNUSEDSIGNAL */
  wire [16:0] perx = {1'b0, per} + {16'd0, ext};   // [16] T1 only
  /* verilator lint_on UNUSEDSIGNAL */
  wire       mp   = run & tk & (cnt == perx[W-1:0]);
  wire       mc   = run & tk & (cnt == {{(W-16){1'b0}}, cmp});

  wire [7:0] rsel_v  = {2'b00, oth_c, oth_p, evr_e};
  wire       restart = go | (rst_en & rsel_v[rst_sel]);
  wire       stop    = stop_u | (oneshot & mp) | (gate & burst_end);
  wire       run_n   = run & ~stop;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt   <= {W{1'b0}};
      run   <= 1'b0;
      wave  <= 1'b0;
      evr_p <= 1'b0;
      evr_c <= 1'b0;
    end else if (srst) begin
      cnt   <= {W{1'b0}};
      run   <= 1'b0;
      wave  <= 1'b0;
      evr_p <= 1'b0;
      evr_c <= 1'b0;
    end else begin
      evr_p <= mp;
      evr_c <= mc;
      if (restart) begin
        cnt  <= {{(W-4){1'b0}}, rld};
        run  <= 1'b1;
        wave <= 1'b0;
      end else begin
        run <= run_n;
        if (mp)
          cnt <= {W{1'b0}};
        else if (run_n & tk)
          cnt <= cnt + {{(W-1){1'b0}}, 1'b1};
        wave <= mp ? 1'b0 : mc ? 1'b1 : wave;
      end
    end
  end

  // ---- T1 fraction (ext kept on restart, cleared by SOFT_RESET)
  generate
    if (IS_T1 != 0) begin : g_frac
      reg       ext_q;
      reg [7:0] acc;
      wire [8:0] sum = {1'b0, acc} + {1'b0, frac};
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          ext_q <= 1'b0;
          acc   <= 8'd0;
        end else if (srst) begin
          ext_q <= 1'b0;
          acc   <= 8'd0;
        end else if (!restart && mp && frac != 8'd0) begin
          ext_q <= sum[8];
          acc   <= sum[7:0];
        end
      end
      assign ext = ext_q;
    end else begin : g_nofrac
      assign ext = 1'b0;
    end
  endgenerate

  assign clk_o   = wave & ~(gate & cnt_zero);
  assign cnt_dbg = cnt[15:0];

endmodule
