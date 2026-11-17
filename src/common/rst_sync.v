// -----------------------------------------------------------------------------
// rst_sync
//
// Reset synchroniser (integration spec §4.1, G-02, D-TOP-5): asserts with the
// pin, releases on the second clk edge after the pin rises. s0 / s1 are reset
// by the raw pin.
// -----------------------------------------------------------------------------

`default_nettype none

module rst_sync (
    input  wire clk,
    input  wire rst_n_i,
    output wire rst_n_o
);

  reg s0, s1;

  always @(posedge clk or negedge rst_n_i)
    if (!rst_n_i) begin
      s0 <= 1'b0;
      s1 <= 1'b0;
    end else begin
      s0 <= 1'b1;
      s1 <= s0;
    end

  assign rst_n_o = s1;

endmodule
