// fv_host_link: formal top for host_link. Holds the clock/reset assumptions,
// instantiates the interface and e2e property modules, and is bound to every
// host_link instance. Ports have the same names, widths and order as the RTL
// (all inputs here, as it only observes). Testplan: ../testplan/host_link_fv_testplan.md

module fv_host_link (
  // Clock and reset
  input  wire        clk,
  input  wire        rst_n,         // active low, async assert, sync release (G-02)

  // SPI target, mode 0. SCK, CS_n and MOSI are asynchronous (P3).
  input  wire        spi_sck_i,     // ui_in[0]
  input  wire        spi_csn_i,     // ui_in[1], active low
  input  wire        spi_mosi_i,    // ui_in[2]
  input  wire        spi_miso_o,    // uo_out[0]

  // System bus, master 0
  input  wire        bus_req_o,
  input  wire        bus_dir_o,     // 1 = write, 0 = read
  input  wire [15:0] bus_addr_o,
  input  wire [15:0] bus_wdata_o,
  input  wire        bus_wready_i,  // write accepted this clock
  input  wire        bus_rready_i,  // read accepted this clock
  input  wire [15:0] bus_rdata_i    // valid the clock after rready
);

  // ---------------------------------------------------------------------------
  // clk, rst_n
  // ---------------------------------------------------------------------------

  // 1001: clk is the only clock (G-01, Impl spec §7). No code: sby runs without
  // multiclock, so every state change is on the rising edge of clk.

  // First-clock flag: 1 only in the first clock of the trace
  logic fv_first_clk = 1'b1;
  always_ff @(posedge clk) fv_first_clk <= 1'b0;

  // rst_n is 0 in the first clock (G-02, D-HL-8)
  asm_1002_reset_in_first_clk: assume property(
    @(posedge clk)
      fv_first_clk -> !rst_n
  );

  // 1003: after the first clock rst_n is free (any clock, mid-frame too) (G-02, V7).
  // No code: a free input already does this, and inputs only change on clk edges.

  // ---------------------------------------------------------------------------
  // Property modules
  // ---------------------------------------------------------------------------

  // Host (SPI) interface properties
  fv_host_link_host_if u_fv_host_link_host_if (.*);

  // System bus interface properties
  fv_host_link_sysbus_if u_fv_host_link_sysbus_if (.*);

  // Properties across both interfaces, data integrity
  fv_host_link_e2e u_fv_host_link_e2e (.*);

endmodule

// Attach to every host_link; the RTL stays free of formal code
bind host_link fv_host_link u_fv_host_link (.*);
