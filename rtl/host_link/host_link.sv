// -----------------------------------------------------------------------------
// host_link
//
// SPI target (mode 0) that turns one 40-bit frame into one 16-bit access on
// the system bus as master 0. Single clock domain; SCK is sampled as data.
//
// Implements docs/Implementation_spec/Host_link_implementation_spec.pdf
// (frozen, 7 Nov 2026), including A-CHG-1 (address before command) and
// A-CHG-2 (one data word per frame, no burst, no auto-increment).
//
// Frame on MOSI, bytes MSB-first, 16-bit fields low byte first:
//   bits  1-8   A[7:0]
//   bits  9-16  A[15:8]
//   bits 17-24  CMD: 0x00 write, 0x80 read (only bit 17 decoded; read issued on it)
//   bits 25-32  D[7:0]  (write) / MISO R[7:0]  (read)
//   bits 33-40  D[15:8] (write) / MISO R[15:8] (read); write issued after bit 40
//
// Structure (48 flops total, all async reset to 0):
//
//   spi ──> host_link_sync (7) ──sel/rise_en/fall_en/mosi_s──┐
//                                                               v
//                         host_link_ctrl (9)  <── wready/rready
//                           │ a_sh, sr_shift, sr_load, miso_en  ──> req, dir
//                           v
//   spi.miso <── host_link_dp (32) <──> addr, wdata, rdata
//
// Ports use the shared bus definitions in rtl/bus_def.
// -----------------------------------------------------------------------------

module host_link (
  clk_rst_if.sink    cr,    // clk, rst_n
  spi_if.target      spi,   // ui_in[0] SCK, ui_in[1] CS_n, ui_in[2] MOSI, uo_out[0] MISO
  sys_bus_if.master  bus    // system bus, master 0 (ADDR_W = DATA_W = 16)
);

  // Sync -> control/datapath
  wire sel, rise_en, fall_en, mosi_s;

  // Control -> datapath
  wire a_sh, sr_shift, sr_load, miso_en;

  host_link_sync u_sync (
    .clk      (cr.clk),
    .rst_n    (cr.rst_n),
    .sck_i    (spi.sck),
    .csn_i    (spi.csn),
    .mosi_i   (spi.mosi),
    .sel      (sel),
    .rise_en  (rise_en),
    .fall_en  (fall_en),
    .mosi_s   (mosi_s)
  );

  host_link_ctrl u_ctrl (
    .clk        (cr.clk),
    .rst_n      (cr.rst_n),
    .sel        (sel),
    .rise_en    (rise_en),
    .fall_en    (fall_en),
    .mosi_s     (mosi_s),
    .wready_i   (bus.wready),
    .rready_i   (bus.rready),
    .req_o      (bus.req),
    .dir_o      (bus.dir),
    .a_sh_o     (a_sh),
    .sr_shift_o (sr_shift),
    .sr_load_o  (sr_load),
    .miso_en_o  (miso_en)
  );

  host_link_dp u_dp (
    .clk      (cr.clk),
    .rst_n    (cr.rst_n),
    .mosi_s   (mosi_s),
    .a_sh     (a_sh),
    .sr_shift (sr_shift),
    .sr_load  (sr_load),
    .miso_en  (miso_en),
    .rdata_i  (bus.rdata),
    .addr_o   (bus.addr),
    .wdata_o  (bus.wdata),
    .miso_o   (spi.miso)
  );

endmodule
