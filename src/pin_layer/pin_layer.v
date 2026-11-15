// -----------------------------------------------------------------------------
// pin_layer
//
// Pin layer (spec pe_pin_layer, docs/Implementation_spec/
// Pin_layer_Implementation_Specification.pdf v1.0; architecture §6.3):
// 43 sources onto 15 output pads through combinational selects, and 16 input
// pads into IN / IN_R through 16 five-flop chains. Bus target 0x1800-0x181F
// that never waits (D-PL-10). D-PL-1 to D-PL-4, D-PL-9 and D-PL-10 confirmed by
// the owner on 15 Nov 2026.
//
//   0x00-0x0E PAD_CFG[p]  W   [5:0] SRC [7:6] MODE; latch, from W+1
//   0x10      GPIO_OUT    RW  [14:0], bit p = pad p (D-PL-6)
//   0x11      GPIO_OE     RW  [14:0]
//   0x12      IN          R   [15:0] = IN in clock W (D-PL-2)
//   0x13      FILT_UI     W   input k (ui k) at [2k+1:2k] (D-PL-7)
//   0x14      FILT_UIO    W   input 8 + k (uio k) at [2k+1:2k]
//   0x15      LOOPBACK    W   bit k = input k
//   others                R 0, writes ignored (PL-15)
//
// Pad index p: 0-6 = uo1-uo7, 7-14 = uio0-uio7. Input index k: 0-7 = ui0-7,
// 8-15 = uio0-7. xr_q is the read data (W+1) and the D input of every latch
// written in W (as D-SC-3). There is no halted-only rule (PL-07).
//
// Storage: xr_q 16, gpio_out 15, gpio_oe 15 (one icg per word, D-PL-3) and
// 16 x (s1, y, c[1:0], in_r) without reset (D-PL-1) = 126 flops; 168 latches
// behind 18 clock gates.
// -----------------------------------------------------------------------------

`default_nettype none

module pin_layer (
  input  wire        clk,
  input  wire        rst_n,
  // bus target, 0x1800-0x181F (req one-hot from the interconnect)
  input  wire        req_i,
  input  wire        dir_i,          // 1 = write
  input  wire [4:0]  addr_i,
  input  wire [15:0] wdata_i,
  output wire        wready_o,       // tied 1 (BUS-06)
  output wire        rready_o,       // tied 1
  output wire [15:0] rdata_o,        // xr_q, valid in the clock after an accepted read
  // TT pads
  input  wire [7:0]  ui_in,
  input  wire [7:0]  uio_in,
  input  wire        miso_i,         // uo_out[0] from the host link, loopback of ui0 only
  output wire [7:1]  uo_out,         // uo_out[0] is driven by the host link at the top level
  output wire [7:0]  uio_out,
  output wire [7:0]  uio_oe,
  // output sources, all from flops
  input  wire [23:0] sc_q_i,         // bit 6n+k = sub-core n output Ok value register
  input  wire [23:0] sc_qoe_i,       // bit 6n+k = its drive-enable register
  input  wire [7:0]  tap0_i,         // SC0 SA taps
  input  wire        tap0_oe_i,      // SC0 O5 drive enable, registered with the taps
  input  wire [7:0]  tap2_i,         // SC2 SA taps
  input  wire        tap2_oe_i,
  input  wire        irq_i,          // host IRQ level from sys_ctrl
  // to every sub-core
  output wire [15:0] in_o,           // IN = y
  output wire [15:0] in_r_o          // IN_R
);

  assign wready_o = 1'b1;
  assign rready_o = 1'b1;

  // ---- bus window (§4.1)
  wire        wr = req_i & dir_i;
  wire [15:0] wd = wdata_i;

  reg  [15:0] xr_q;
  reg  [14:0] gpio_out, gpio_oe;
  wire [15:0] y;

  reg [15:0] rdm;
  always @(*) begin
    case (addr_i)
      5'h10:   rdm = {1'b0, gpio_out};
      5'h11:   rdm = {1'b0, gpio_oe};
      5'h12:   rdm = y;
      default: rdm = 16'd0;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      xr_q <= 16'd0;
    else
      xr_q <= wr ? wd : rdm;
  end
  assign rdata_o = xr_q;

  // ---- GPIO_OUT / GPIO_OE, one clock gate per word (D-PL-3)
  wire g_out, g_oe;
  icg u_icg_out (.clk(clk), .en(wr & (addr_i == 5'h10)), .gclk(g_out));
  icg u_icg_oe  (.clk(clk), .en(wr & (addr_i == 5'h11)), .gclk(g_oe));
  always @(posedge g_out or negedge rst_n)
    if (!rst_n) gpio_out <= 15'd0; else gpio_out <= wd[14:0];
  always @(posedge g_oe or negedge rst_n)
    if (!rst_n) gpio_oe <= 15'd0; else gpio_oe <= wd[14:0];

  // ---- configuration latches: PAD_CFG x15, FILT_UI, FILT_UIO, LOOPBACK
  wire [119:0] pad_cfg;              // pad p at [8p +: 8]
  wire [31:0]  filt;                 // input k at [2k +: 2]
  wire [15:0]  lb;

  genvar p, k;
  generate
    for (p = 0; p < 15; p = p + 1) begin : g_cfg
      wire gclk;
      icg u_icg (.clk(clk), .en(wr & (addr_i == p)), .gclk(gclk));
      lword #(.W(8)) u_l (.rst_n(rst_n), .g(gclk), .d(xr_q[7:0]), .q(pad_cfg[8*p +: 8]));
    end
  endgenerate

  wire g_fui, g_fuio, g_lb;
  icg u_icg_fui  (.clk(clk), .en(wr & (addr_i == 5'h13)), .gclk(g_fui));
  icg u_icg_fuio (.clk(clk), .en(wr & (addr_i == 5'h14)), .gclk(g_fuio));
  icg u_icg_lb   (.clk(clk), .en(wr & (addr_i == 5'h15)), .gclk(g_lb));
  lword #(.W(16)) u_fui  (.rst_n(rst_n), .g(g_fui),  .d(xr_q), .q(filt[15:0]));
  lword #(.W(16)) u_fuio (.rst_n(rst_n), .g(g_fuio), .d(xr_q), .q(filt[31:16]));
  lword #(.W(16)) u_lb   (.rst_n(rst_n), .g(g_lb),   .d(xr_q), .q(lb));

  // ---- pad slices (§4.2)
  wire [14:0] pout, poe;
  generate
    for (p = 0; p < 15; p = p + 1) begin : g_pad
      pin_layer_pad #(.IS_UIO(p >= 7)) u_pad (
        .cfg(pad_cfg[8*p +: 8]), .gpio_out(gpio_out[p]), .gpio_oe(gpio_oe[p]),
        .sc_qoe_i(sc_qoe_i), .tap0_oe_i(tap0_oe_i), .tap2_oe_i(tap2_oe_i), .irq_i(irq_i),
        .sc_q_i(sc_q_i), .tap0_i(tap0_i), .tap2_i(tap2_i), .out(pout[p]), .oe(poe[p]));
    end
  endgenerate

  assign uo_out  = pout[6:0];
  assign uio_out = pout[14:7];
  assign uio_oe  = poe[14:7];

  // ---- input chains (§4.3)
  wire [15:0] pad = {uio_in, ui_in};
  wire [15:0] lbv = {uio_out | ~uio_oe, uo_out, miso_i};   // released uio reads 1
  generate
    for (k = 0; k < 16; k = k + 1) begin : g_in
      pin_layer_in u_in (
        .clk(clk), .pad(pad[k]), .lbv(lbv[k]), .lb(lb[k]), .f(filt[2*k +: 2]),
        .y(y[k]), .in_r(in_r_o[k]));
    end
  endgenerate

  assign in_o = y;

  // poe[6:0] (uo pads) is constant 0
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = &{1'b0, poe[6:0]};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
