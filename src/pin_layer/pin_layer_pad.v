// -----------------------------------------------------------------------------
// pin_layer_pad
//
// One pad slice p (pin-layer spec §4.2; PL-03, PL-04, PL-06, D-PL-8, D-PL-9).
// Combinational. SRC = cfg[5:0] (g = SRC[5:3], i = SRC[2:0]),
// MODE = cfg[7:6] (0 push-pull, 1 open-drain, 2/3 input).
//
//   gv = {0, 0, tap2[i], tap0[i], sc_q[16+i], sc_q[8+i], sc_q[i],
//         (i == 1 & gpio_out) | (i == 2 & irq)}[g];   v = gv
//   drive = !MODE[1]
//   uo pad (IS_UIO = 0):  out = drive & v                     (no output enable)
//   uio pad (IS_UIO = 1): ge = {0, 0, tap2_oe, tap0_oe, sc_qoe[16+i],
//                               sc_qoe[8+i], sc_qoe[i], (i == 1 & gpio_oe) | (i == 2)}[g]
//                         out = (MODE == 0) & v
//                         oe  = drive & e & !(MODE[0] & v)    (open-drain drives low only)
//
// Codes: 0 none, 1 GPIO, 2 host IRQ, 3-7 none, 8 + 6n + k sub-core n output k,
// 32-39 SC0 SA taps, 40-47 SC2 SA taps, 48-63 none. SRC = none gives v = e = 0.
// -----------------------------------------------------------------------------

`default_nettype none

module pin_layer_pad #(
  parameter IS_UIO = 0
) (
  input  wire [7:0]  cfg,         // PAD_CFG: [5:0] SRC, [7:6] MODE
  input  wire        gpio_out,
  /* verilator lint_off UNUSEDSIGNAL */
  input  wire        gpio_oe,     // uio pads only
  input  wire [23:0] sc_qoe_i,    // uio pads only
  input  wire        tap0_oe_i,   // uio pads only
  input  wire        tap2_oe_i,   // uio pads only
  /* verilator lint_on UNUSEDSIGNAL */
  input  wire        irq_i,
  input  wire [23:0] sc_q_i,
  input  wire [7:0]  tap0_i,
  input  wire [7:0]  tap2_i,
  output wire        out,
  output wire        oe
);

  wire [2:0] g    = cfg[5:3];
  wire [2:0] i    = cfg[2:0];
  /* verilator lint_off UNUSEDSIGNAL */
  wire [1:0] mode = cfg[7:6];       // [0] unused on uo pads (D-PL-8)
  /* verilator lint_on UNUSEDSIGNAL */

  wire [7:0] gv = {1'b0, 1'b0, tap2_i[i], tap0_i[i], sc_q_i[{2'b10, i}], sc_q_i[{2'b01, i}], sc_q_i[{2'b00, i}],
                   ((i == 3'd1) & gpio_out) | ((i == 3'd2) & irq_i)};
  wire v     = gv[g];
  wire drive = ~mode[1];

  generate
    if (IS_UIO != 0) begin : g_uio
      wire [7:0] ge = {1'b0, 1'b0, tap2_oe_i, tap0_oe_i, sc_qoe_i[{2'b10, i}], sc_qoe_i[{2'b01, i}], sc_qoe_i[{2'b00, i}],
                       ((i == 3'd1) & gpio_oe) | (i == 3'd2)};
      wire e = ge[g];
      assign out = (mode == 2'd0) & v;
      assign oe  = drive & e & ~(mode[0] & v);
    end else begin : g_uo
      assign out = drive & v;
      assign oe  = 1'b0;
    end
  endgenerate

endmodule
