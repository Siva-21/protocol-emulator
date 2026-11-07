// -----------------------------------------------------------------------------
// spi_if
//
// 4-wire SPI bundle, mode 0 (CPOL 0, CPHA 0), bytes MSB-first.
// Pin mapping on the chip: ui_in[0] = SCK, ui_in[1] = CS_n, ui_in[2] = MOSI,
// uo_out[0] = MISO.
//
// The target side treats SCK, CS_n and MOSI as asynchronous data: each goes
// straight into a synchroniser flop with no logic in front of it (P3).
// -----------------------------------------------------------------------------

interface spi_if;

  logic sck;
  logic csn;    // active low chip select
  logic mosi;
  logic miso;

  // External host (RP2350, or a testbench BFM)
  modport host (
    output sck,
    output csn,
    output mosi,
    input  miso
  );

  // On-chip SPI target (host_link)
  modport target (
    input  sck,
    input  csn,
    input  mosi,
    output miso
  );

  // Passive observer (assertions, scoreboards)
  modport monitor (
    input sck,
    input csn,
    input mosi,
    input miso
  );

endinterface
