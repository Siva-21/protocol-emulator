/*
 * tt_um_protocol_emulator
 *
 * Tiny Tapeout top of the Protocol Emulator (integration spec
 * docs/Integration_spec/Top_level_Integration_Specification_v1.pdf v1.0, §4.2;
 * D-TOP-1 to D-TOP-6 and D-TOP-8 to D-TOP-10 confirmed by the owner on
 * 15 Nov 2026; D-TOP-7 not adopted, see below). Eight instances
 * and wiring; the only new logic is the 2-flop reset synchroniser rst_sync
 * (D-TOP-5). Block modules carry the spec names without the pe_ prefix.
 *
 *   u_rst  rst_sync    raw rst_n pin -> rst_rst_n_o, the reset of every block
 *                      (src/common/rst_sync.v)
 *   u_hl   host_link   SPI target on ui0-ui2, MISO on uo0; bus master 0
 *   u_bus  sysbus      host > core arbitration, 16-bit decode, read mux
 *   u_mcu  main_ss     main core, SRAM macro, CRC + bit-stream unit; master 1
 *   u_sys  sys_ctrl    run / halt strobes, ticks, IRQ, doorbell, WAIT vector
 *   u_p0   sc_pair     SC0 (master) + SC1
 *   u_p1   sc_pair     SC2 (master) + SC3
 *   u_pl   pin_layer   15 pad selects, 16 input chains (IN, IN_R)
 *
 * A net is named after its driver: <instance without u_>_<port>. Sideband
 * (SIG, status, run / halt strobes, ticks, WAIT, IRQ, IN / IN_R, pad sources)
 * is plain wiring (D-TOP-6). Open by design: the ready outputs of sys_ctrl and
 * the pin layer (tied 1 inside, D-TOP-8); ena (G-08). No IN / IN_R wire to
 * sys_ctrl (D-TOP-10). Plain Verilog only, so the TT Yosys frontend reads it.
 *
 * sc_pair keeps its block port list (every per-sub-core port with a [1:0]
 * index), not the narrower list of integration spec §3.3 (D-TOP-7): the top
 * uses the master's taps tap_o[7:0] / tap_oe_o[0] and leaves the partner's
 * taps (always 0, D-SC-14) and the sub-cores' wready_o / rready_o (tied 1,
 * D-BUS-9) unused. Same netlist after synthesis.
 */

`default_nettype none

module tt_um_protocol_emulator (
    input  wire [7:0] ui_in,    // ui0 SCK, ui1 CS_n, ui2 MOSI (host link); all 8 to the pin layer
    output wire [7:0] uo_out,   // uo0 MISO; uo1-uo7 pads p = 0-6
    input  wire [7:0] uio_in,   // inputs 8-15
    output wire [7:0] uio_out,  // pads p = 7-14
    output wire [7:0] uio_oe,
    input  wire       ena,      // unused (G-08)
    input  wire       clk,
    input  wire       rst_n     // raw reset from the TT harness; synchronised in u_rst
);

  wire        rst_rst_n_o;
  wire        hl_miso_o, hl_req_o, hl_dir_o;
  wire [15:0] hl_addr_o, hl_wdata_o;
  wire        bus_h_wready_o, bus_h_rready_o;
  wire [15:0] bus_h_rdata_o;
  wire        bus_m_wready_o, bus_m_rready_o;
  wire [15:0] bus_m_rdata_o;
  wire        bus_t_req_o, bus_t_dir_o;
  wire [15:0] bus_t_addr_o, bus_t_wdata_o;
  wire        bus_sys_req_o;
  wire [3:0]  bus_sc_req_o;
  wire        bus_pl_req_o, bus_c_dir_o;
  wire [15:0] bus_c_addr_o, bus_c_wdata_o;
  wire        mcu_t_wready_o, mcu_t_rready_o;
  wire [15:0] mcu_t_rdata_o;
  wire        mcu_m_req_o, mcu_m_dir_o;
  wire [15:0] mcu_m_addr_o, mcu_m_wdata_o;
  wire        mcu_mc_halt_o, mcu_mc_irq_o, mcu_crc_idle_o, mcu_bs_valid_o;
  wire        sys_wready_o, sys_rready_o;
  wire [15:0] sys_rdata_o;
  wire        sys_mc_run_o;
  wire [15:0] sys_wait_o;
  wire [3:0]  sys_sc_run_o, sys_sc_halt_o;
  wire [2:0]  sys_tick_o;
  wire        sys_irq_o;
  wire [31:0] p0_rdata_o, p1_rdata_o;
  wire [11:0] p0_q_o, p0_qoe_o, p1_q_o, p1_qoe_o;
  wire [15:0] p0_tap_o, p1_tap_o;            // [7:0] master taps; [15:8] partner, 0
  wire [1:0]  p0_tap_oe_o, p1_tap_oe_o;      // [0] master; [1] partner, 0
  wire [1:0]  p0_wready_o, p0_rready_o, p1_wready_o, p1_rready_o;
  wire [1:0]  p0_fa_space_o, p0_fb_ne_o, p0_ntf_o, p0_halted_o, p0_err_o;
  wire [1:0]  p1_fa_space_o, p1_fb_ne_o, p1_ntf_o, p1_halted_o, p1_err_o;
  wire [3:0]  p0_sig_o, p1_sig_o;
  wire        pl_wready_o, pl_rready_o;
  wire [15:0] pl_rdata_o;
  wire [6:0]  pl_uo_out;
  wire [7:0]  pl_uio_out, pl_uio_oe;
  wire [15:0] pl_in_o, pl_in_r_o;

  rst_sync u_rst (
      .clk    (clk),
      .rst_n_i(rst_n),
      .rst_n_o(rst_rst_n_o)
  );

  host_link u_hl (
      .clk         (clk),
      .rst_n       (rst_rst_n_o),
      .spi_sck_i   (ui_in[0]),
      .spi_csn_i   (ui_in[1]),
      .spi_mosi_i  (ui_in[2]),
      .spi_miso_o  (hl_miso_o),
      .bus_req_o   (hl_req_o),
      .bus_dir_o   (hl_dir_o),
      .bus_addr_o  (hl_addr_o),
      .bus_wdata_o (hl_wdata_o),
      .bus_wready_i(bus_h_wready_o),
      .bus_rready_i(bus_h_rready_o),
      .bus_rdata_i (bus_h_rdata_o)
  );

  sysbus u_bus (
      .clk        (clk),
      .rst_n      (rst_rst_n_o),
      .h_req_i    (hl_req_o),
      .h_dir_i    (hl_dir_o),
      .h_addr_i   (hl_addr_o),
      .h_wdata_i  (hl_wdata_o),
      .h_wready_o (bus_h_wready_o),
      .h_rready_o (bus_h_rready_o),
      .h_rdata_o  (bus_h_rdata_o),
      .m_req_i    (mcu_m_req_o),
      .m_dir_i    (mcu_m_dir_o),
      .m_addr_i   (mcu_m_addr_o),
      .m_wdata_i  (mcu_m_wdata_o),
      .m_wready_o (bus_m_wready_o),
      .m_rready_o (bus_m_rready_o),
      .m_rdata_o  (bus_m_rdata_o),
      .t_req_o    (bus_t_req_o),
      .t_dir_o    (bus_t_dir_o),
      .t_addr_o   (bus_t_addr_o),
      .t_wdata_o  (bus_t_wdata_o),
      .t_wready_i (mcu_t_wready_o),
      .t_rready_i (mcu_t_rready_o),
      .t_rdata_i  (mcu_t_rdata_o),
      .sys_req_o  (bus_sys_req_o),
      .sc_req_o   (bus_sc_req_o),
      .pl_req_o   (bus_pl_req_o),
      .c_dir_o    (bus_c_dir_o),
      .c_addr_o   (bus_c_addr_o),
      .c_wdata_o  (bus_c_wdata_o),
      .sys_rdata_i(sys_rdata_o),
      .sc_rdata_i ({p1_rdata_o, p0_rdata_o}),
      .pl_rdata_i (pl_rdata_o)
  );

  main_ss u_mcu (
      .clk       (clk),
      .rst_n     (rst_rst_n_o),
      .t_req_i   (bus_t_req_o),
      .t_dir_i   (bus_t_dir_o),
      .t_addr_i  (bus_t_addr_o),
      .t_wdata_i (bus_t_wdata_o),
      .t_wready_o(mcu_t_wready_o),
      .t_rready_o(mcu_t_rready_o),
      .t_rdata_o (mcu_t_rdata_o),
      .m_req_o   (mcu_m_req_o),
      .m_dir_o   (mcu_m_dir_o),
      .m_addr_o  (mcu_m_addr_o),
      .m_wdata_o (mcu_m_wdata_o),
      .m_wready_i(bus_m_wready_o),
      .m_rready_i(bus_m_rready_o),
      .m_rdata_i (bus_m_rdata_o),
      .mc_run_i  (sys_mc_run_o),
      .mc_halt_o (mcu_mc_halt_o),
      .mc_irq_o  (mcu_mc_irq_o),
      .wait_i    (sys_wait_o),
      .crc_idle_o(mcu_crc_idle_o),
      .bs_valid_o(mcu_bs_valid_o)
  );

  sys_ctrl u_sys (
      .clk          (clk),
      .rst_n        (rst_rst_n_o),
      .req_i        (bus_sys_req_o),
      .dir_i        (bus_c_dir_o),
      .addr_i       (bus_c_addr_o),
      .wdata_i      (bus_c_wdata_o),
      .wready_o     (sys_wready_o),
      .rready_o     (sys_rready_o),
      .rdata_o      (sys_rdata_o),
      .mc_run_o     (sys_mc_run_o),
      .mc_halt_i    (mcu_mc_halt_o),
      .mc_irq_i     (mcu_mc_irq_o),
      .wait_o       (sys_wait_o),
      .crc_idle_i   (mcu_crc_idle_o),
      .bs_valid_i   (mcu_bs_valid_o),
      .sc_run_o     (sys_sc_run_o),
      .sc_halt_o    (sys_sc_halt_o),
      .tick_o       (sys_tick_o),
      .sc_fa_space_i({p1_fa_space_o, p0_fa_space_o}),
      .sc_fb_ne_i   ({p1_fb_ne_o, p0_fb_ne_o}),
      .sc_ntf_i     ({p1_ntf_o, p0_ntf_o}),
      .sc_halted_i  ({p1_halted_o, p0_halted_o}),
      .sc_err_i     ({p1_err_o, p0_err_o}),
      .irq_o        (sys_irq_o)
  );

  sc_pair #(.PAIR(0)) u_p0 (
      .clk       (clk),
      .rst_n     (rst_rst_n_o),
      .req_i     (bus_sc_req_o[1:0]),
      .dir_i     (bus_c_dir_o),
      .addr_i    (bus_c_addr_o[6:0]),
      .wdata_i   (bus_c_wdata_o),
      .wready_o  (p0_wready_o),
      .rready_o  (p0_rready_o),
      .rdata_o   (p0_rdata_o),
      .in_i      (pl_in_o),
      .in_r_i    (pl_in_r_o),
      .q_o       (p0_q_o),
      .qoe_o     (p0_qoe_o),
      .tap_o     (p0_tap_o),
      .tap_oe_o  (p0_tap_oe_o),
      .run_i     (sys_sc_run_o[1:0]),
      .halt_i    (sys_sc_halt_o[1:0]),
      .tick_i    (sys_tick_o),
      .fa_space_o(p0_fa_space_o),
      .fb_ne_o   (p0_fb_ne_o),
      .ntf_o     (p0_ntf_o),
      .halted_o  (p0_halted_o),
      .err_o     (p0_err_o),
      .sig_o     (p0_sig_o),
      .sig_i     ({p1_sig_o, p0_sig_o})
  );

  sc_pair #(.PAIR(1)) u_p1 (
      .clk       (clk),
      .rst_n     (rst_rst_n_o),
      .req_i     (bus_sc_req_o[3:2]),
      .dir_i     (bus_c_dir_o),
      .addr_i    (bus_c_addr_o[6:0]),
      .wdata_i   (bus_c_wdata_o),
      .wready_o  (p1_wready_o),
      .rready_o  (p1_rready_o),
      .rdata_o   (p1_rdata_o),
      .in_i      (pl_in_o),
      .in_r_i    (pl_in_r_o),
      .q_o       (p1_q_o),
      .qoe_o     (p1_qoe_o),
      .tap_o     (p1_tap_o),
      .tap_oe_o  (p1_tap_oe_o),
      .run_i     (sys_sc_run_o[3:2]),
      .halt_i    (sys_sc_halt_o[3:2]),
      .tick_i    (sys_tick_o),
      .fa_space_o(p1_fa_space_o),
      .fb_ne_o   (p1_fb_ne_o),
      .ntf_o     (p1_ntf_o),
      .halted_o  (p1_halted_o),
      .err_o     (p1_err_o),
      .sig_o     (p1_sig_o),
      .sig_i     ({p1_sig_o, p0_sig_o})
  );

  pin_layer u_pl (
      .clk      (clk),
      .rst_n    (rst_rst_n_o),
      .req_i    (bus_pl_req_o),
      .dir_i    (bus_c_dir_o),
      .addr_i   (bus_c_addr_o[4:0]),
      .wdata_i  (bus_c_wdata_o),
      .wready_o (pl_wready_o),
      .rready_o (pl_rready_o),
      .rdata_o  (pl_rdata_o),
      .ui_in    (ui_in),
      .uio_in   (uio_in),
      .miso_i   (hl_miso_o),
      .uo_out   (pl_uo_out),
      .uio_out  (pl_uio_out),
      .uio_oe   (pl_uio_oe),
      .sc_q_i   ({p1_q_o, p0_q_o}),
      .sc_qoe_i ({p1_qoe_o, p0_qoe_o}),
      .tap0_i   (p0_tap_o[7:0]),
      .tap0_oe_i(p0_tap_oe_o[0]),
      .tap2_i   (p1_tap_o[7:0]),
      .tap2_oe_i(p1_tap_oe_o[0]),
      .irq_i    (sys_irq_o),
      .in_o     (pl_in_o),
      .in_r_o   (pl_in_r_o)
  );

  assign uo_out  = {pl_uo_out, hl_miso_o};
  assign uio_out = pl_uio_out;
  assign uio_oe  = pl_uio_oe;

  // Unused by design: ena (G-08), chip-bus target ready outputs (D-TOP-8, and
  // the sub-cores' inside the pairs), the partners' taps (always 0, D-SC-14).
  wire _unused = &{1'b0, ena, sys_wready_o, sys_rready_o, pl_wready_o, pl_rready_o,
                   p0_wready_o, p0_rready_o, p1_wready_o, p1_rready_o,
                   p0_tap_o[15:8], p0_tap_oe_o[1], p1_tap_o[15:8], p1_tap_oe_o[1]};

endmodule
