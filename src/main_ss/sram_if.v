// -----------------------------------------------------------------------------
// sram_if
//
// SRAM port logic (main_ss spec §7, figure F4, D-MC-9): one operation
// per clock, priority host > core data > core fetch (MEM-02), and the
// RM_IHPSG13_1P_512x16_c2_bm_bist macro instance.
//
//   - A_REN and A_WEN are never 1 together (no write-through).
//   - A_DOUT is updated at the clock edge of a read and holds otherwise; the
//     core uses it as its instruction register (D-MC-4).
//   - A_DLY = 1 (mandatory), BIST tied off.
//
// Flops: 0 (plus the macro).
// -----------------------------------------------------------------------------

`default_nettype none

module sram_if (
  input  wire        clk,
  // Host (bus target), highest priority
  input  wire        h_req,      // h_sram
  input  wire        h_we,       // t_dir_i
  input  wire [8:0]  h_addr,
  input  wire [15:0] h_wdata,
  // Core data access (dreq_o, dwe_o); issued only when the host is idle
  input  wire        d_req,
  input  wire        d_we,
  input  wire [8:0]  d_addr,
  input  wire [15:0] d_din,
  input  wire [15:0] d_bm,
  // Core fetch (freq_o)
  input  wire        f_req,
  input  wire [8:0]  f_addr,
  output wire [15:0] dout        // A_DOUT
);

  wire sel_h = h_req;
  wire sel_d = ~h_req & d_req;
  wire sel_f = ~h_req & ~d_req & f_req;

  wire        a_men  = sel_h | sel_d | sel_f;
  wire        a_wen  = (sel_h & h_we) | (sel_d & d_we);
  wire        a_ren  = a_men & ~a_wen;
  wire [8:0]  a_addr = sel_h ? h_addr  : sel_d ? d_addr : f_addr;
  wire [15:0] a_din  = sel_h ? h_wdata : d_din;
  wire [15:0] a_bm   = sel_h ? 16'hFFFF : sel_d ? d_bm : 16'hFFFF;

  RM_IHPSG13_1P_512x16_c2_bm_bist u_mem (
    .A_CLK       (clk),
    .A_MEN       (a_men),
    .A_WEN       (a_wen),
    .A_REN       (a_ren),
    .A_ADDR      (a_addr),
    .A_DIN       (a_din),
    .A_DLY       (1'b1),
    .A_DOUT      (dout),
    .A_BM        (a_bm),
    .A_BIST_CLK  (1'b0),
    .A_BIST_EN   (1'b0),
    .A_BIST_MEN  (1'b0),
    .A_BIST_WEN  (1'b0),
    .A_BIST_REN  (1'b0),
    .A_BIST_ADDR (9'd0),
    .A_BIST_DIN  (16'd0),
    .A_BIST_BM   (16'd0)
  );

endmodule
