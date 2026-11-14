/*
 * Tiny Tapeout top for the Protocol Emulator.
 *
 * Placeholder until the real top is integrated: uses every input so LibreLane's
 * disconnected-pin check passes. uo_out is a register of ui_in ^ uio_in (loaded
 * while ena is high); uio is unused (all inputs, outputs driven low).
 * Plain Verilog only (no SystemVerilog interfaces), so the TT tooling's default
 * Yosys frontend reads it.
 */

`default_nettype none

module tt_um_protocol_emulator_placeholder (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  reg [7:0] r;

  always @(posedge clk or negedge rst_n)
    if (!rst_n)   r <= 8'h00;
    else if (ena) r <= ui_in ^ uio_in;

  assign uo_out  = r;
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

endmodule

`default_nettype wire
