// -----------------------------------------------------------------------------
// pin_layer_in
//
// One input chain k (pin-layer spec §4.3, §5; PL-08 to PL-12, D-PL-1,
// D-PL-5, O-08): loopback mux -> s1 -> glitch filter y (= IN) -> in_r (IN_R).
//
//   s1_n   = lb ? lbv : pad              (the only logic in front of s1)
//   m      = s1 ^ y
//   upd    = (f == 0) | (m & c == f)
//   y_n    = upd ? s1 : y
//   c_n    = (f != 0 & m & !upd) ? c + 1 : 0
//   in_r_n = y
//
// With f = 0, y is the plain second synchroniser flop. With f = 1-3 a level
// reaches IN only after f + 1 equal samples of s1, exactly f clocks later.
// The five flops have no reset (D-PL-1): with the clock running during rst_n
// they load the pad levels, so no false edge appears at release.
// -----------------------------------------------------------------------------

`default_nettype none

module pin_layer_in (
  input  wire       clk,
  input  wire       pad,          // asynchronous pad level
  input  wire       lbv,          // loopback value (this chip's own driver)
  input  wire       lb,           // LOOPBACK bit
  input  wire [1:0] f,            // FILT
  output reg        y,            // IN
  output reg        in_r          // IN_R
);

  reg       s1;
  reg [1:0] c;

  wire m   = s1 ^ y;
  wire upd = (f == 2'd0) | (m & (c == f));

  always @(posedge clk) begin
    s1   <= lb ? lbv : pad;
    y    <= upd ? s1 : y;
    c    <= ((f != 2'd0) & m & ~upd) ? c + 2'd1 : 2'd0;
    in_r <= y;
  end

endmodule
