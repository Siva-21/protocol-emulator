// -----------------------------------------------------------------------------
// clk_rst_if
//
// Clock and reset bundle shared by every block. The design has a single clock
// domain (clk); no generated or gated clocks (G-01).
//
// rst_n is the synchronised reset: asynchronous assert, synchronous release
// (G-02). The reset synchroniser lives in the system controller / top level,
// which drives this interface through the `source` modport.
// -----------------------------------------------------------------------------

interface clk_rst_if;

  logic clk;
  logic rst_n;   // active low, async assert, sync release

  // Driven by the clock/reset generator (top level or testbench)
  modport source (
    output clk,
    output rst_n
  );

  // Consumed by every synchronous block
  modport sink (
    input clk,
    input rst_n
  );

endinterface
