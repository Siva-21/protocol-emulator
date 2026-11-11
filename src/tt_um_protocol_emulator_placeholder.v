/*
 * Tiny Tapeout top for the Protocol Emulator.
 *
 * PLACEHOLDER: no logic yet, all outputs tied low. Plain Verilog only (no
 * SystemVerilog interfaces), so the TT tooling's default Yosys frontend reads it.
 */

`default_nettype none

module tt_um_protocol_emulator_placeholder (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  assign uo_out  = 8'h00;
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, ui_in, uio_in, 1'b0};

endmodule

`default_nettype wire
