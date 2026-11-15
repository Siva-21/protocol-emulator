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
// System bus protocol (BUS-02 req/dir/ready, D-HL-7):
//   - The master raises req with dir/addr (and wdata when dir = 1) and holds
//     them stable until the access is accepted.
//   - Write (dir = 1): accepted in the clock where wready = 1; the write takes
//     effect at the edge ending that clock, and req drops at that edge.
//   - Read  (dir = 0): accepted in the clock where rready = 1 (side effect at
//     the edge ending that clock); rdata is valid the clock after rready.
//   - wready/rready are combinational from the interconnect in the same clock
//     and must not depend combinationally on wdata.
//   - An unmapped address answers ready = 1 and rdata = 0.
//
// Structure (48 flops total, all async reset to 0):
//
//   spi ──> host_link_sync (7) ──sel/rise_en/fall_en/mosi_s──┐
//                                                               v
//                         host_link_ctrl (9)  <── wready/rready
//                           │ a_sh, sr_shift, sr_load, miso_en  ──> req, dir
//                           v
//   miso <── host_link_dp (32) <──> addr, wdata, rdata
// -----------------------------------------------------------------------------

module host_link (
  // Clock and reset
  input  wire        clk,
  input  wire        rst_n,         // active low, async assert, sync release (G-02)

  // SPI target, mode 0. SCK, CS_n and MOSI are asynchronous (P3).
  input  wire        spi_sck_i,     // ui_in[0]
  input  wire        spi_csn_i,     // ui_in[1], active low
  input  wire        spi_mosi_i,    // ui_in[2]
  output wire        spi_miso_o,    // uo_out[0]

  // System bus, master 0
  output wire        bus_req_o,
  output wire        bus_dir_o,     // 1 = write, 0 = read
  output wire [15:0] bus_addr_o,
  output wire [15:0] bus_wdata_o,
  input  wire        bus_wready_i,  // write accepted this clock
  input  wire        bus_rready_i,  // read accepted this clock
  input  wire [15:0] bus_rdata_i    // valid the clock after rready
);

  // Sync -> control/datapath
  wire sel, rise_en, fall_en, mosi_s;

  // Control -> datapath
  wire a_sh, sr_shift, sr_load, miso_en;

  host_link_sync u_sync (
    .clk      (clk),
    .rst_n    (rst_n),
    .sck_i    (spi_sck_i),
    .csn_i    (spi_csn_i),
    .mosi_i   (spi_mosi_i),
    .sel      (sel),
    .rise_en  (rise_en),
    .fall_en  (fall_en),
    .mosi_s   (mosi_s)
  );

  host_link_ctrl u_ctrl (
    .clk        (clk),
    .rst_n      (rst_n),
    .sel        (sel),
    .rise_en    (rise_en),
    .fall_en    (fall_en),
    .mosi_s     (mosi_s),
    .wready_i   (bus_wready_i),
    .rready_i   (bus_rready_i),
    .req_o      (bus_req_o),
    .dir_o      (bus_dir_o),
    .a_sh_o     (a_sh),
    .sr_shift_o (sr_shift),
    .sr_load_o  (sr_load),
    .miso_en_o  (miso_en)
  );

  host_link_dp u_dp (
    .clk      (clk),
    .rst_n    (rst_n),
    .mosi_s   (mosi_s),
    .a_sh     (a_sh),
    .sr_shift (sr_shift),
    .sr_load  (sr_load),
    .miso_en  (miso_en),
    .rdata_i  (bus_rdata_i),
    .addr_o   (bus_addr_o),
    .wdata_o  (bus_wdata_o),
    .miso_o   (spi_miso_o)
  );

endmodule
