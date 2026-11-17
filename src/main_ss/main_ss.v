// -----------------------------------------------------------------------------
// main_ss
//
// Main-core subsystem, pe_mcu_subsys in the spec (docs/Implementation_spec/
// Main_Subsystem_implementation_specification.pdf, v1.1, 15 Nov 2026): the
// main core, the single SRAM macro with its port logic, and the CRC unit
// extended with the bit-stream unit. Replaces main_core / sram_if of
// requirements §2.
//
// Hierarchy (spec §2.1, figure F1; spec names have a pe_ prefix):
//   main_ss                    top: local decode, t_rdata mux, instances
//   ├── u_core  mc_core        control, decode, register file, ALU, bus master
//   │   └── g_row[1..7].u_icg  icg, one clock gate per register-file row
//   ├── u_sram  sram_if        port priority mux + macro instance
//   │   └── u_mem  RM_IHPSG13_1P_512x16_c2_bm_bist
//   └── u_crc   crc_bs         CRC + bit-stream unit, registers 0x1C10-0x1C19
//
// Bus target: the interconnect raises t_req_i only for 0x0000-0x01FF and
// 0x1C10-0x1C1F, one select (D-MC-8). t_addr_i[12] = 0 selects the SRAM
// (t_addr_i[8:0]), 1 the CRC block (t_addr_i[3:0]). The host is first at
// every shared resource. A DATA write and a VAL_L/VAL_H read wait while the
// CRC unit is busy; every other access is accepted at once.
//
// Bus master: the core's accesses to any other address (A-CHG-8: the core's
// SRAM / CRC-block accesses proceed while the host is on the chip bus).
//
// System control: mc_run_i from sys_ctrl; mc_halt_o / mc_irq_o in the clock a
// HALT / IRQ instruction executes; crc_idle_o = WAIT bit 13, bs_valid_o =
// WAIT bit 15 (A-CHG-7).
//
// Flops: 278 (core 130, CRC block 147, rsel_q 1) plus the SRAM macro.
// -----------------------------------------------------------------------------

`default_nettype none

module main_ss (
  input  wire        clk,
  input  wire        rst_n,
  // Bus target (host link via the interconnect): 0x0000-0x01FF and 0x1C10-0x1C1F, one select
  input  wire        t_req_i,
  input  wire        t_dir_i,        // 1 = write
  /* verilator lint_off UNUSEDSIGNAL */
  input  wire [15:0] t_addr_i,       // [12] SRAM / CRC, [8:0] SRAM word, [3:0] CRC offset
  /* verilator lint_on UNUSEDSIGNAL */
  input  wire [15:0] t_wdata_i,
  output wire        t_wready_o,
  output wire        t_rready_o,
  output wire [15:0] t_rdata_o,      // valid in the clock after an accepted read
  // Bus master (core): every other address
  output wire        m_req_o,
  output wire        m_dir_o,        // 1 = write
  output wire [15:0] m_addr_o,
  output wire [15:0] m_wdata_o,
  input  wire        m_wready_i,     // 0 in clocks where the host owns the chip bus
  input  wire        m_rready_i,
  input  wire [15:0] m_rdata_i,      // valid in the clock after an accepted read
  // System control
  input  wire        mc_run_i,
  output wire        mc_halt_o,      // 1 in the clock HALT executes
  output wire        mc_irq_o,       // 1 in the clock IRQ executes
  input  wire [15:0] wait_i,         // WAIT vector from sys_ctrl
  output wire        crc_idle_o,     // WAIT bit 13
  output wire        bs_valid_o      // WAIT bit 15
);

  wire        crc_busy;
  wire [15:0] crc_rdata_q;
  wire        crc_outv;
  wire [15:0] sram_dout;

  // Core -> SRAM / CRC block
  wire        core_dreq, core_dwe, core_freq;
  wire [8:0]  core_daddr, core_faddr;
  wire [15:0] core_ddin, core_dbm;
  wire        core_creq, core_cwe;
  wire [3:0]  core_coff;
  wire [15:0] core_cwdata;

  // ---------------------------------------------------------------------------
  // Target port (§3.2)
  // ---------------------------------------------------------------------------
  wire [3:0] t_off = t_addr_i[3:0];

  assign t_wready_o = ~(t_addr_i[12] & (t_off == 4'h3) & crc_busy);                      // DATA write waits while busy
  assign t_rready_o = ~(t_addr_i[12] & ((t_off == 4'h4) | (t_off == 4'h5)) & crc_busy);  // VAL read waits

  // ---------------------------------------------------------------------------
  // Host request classification (§4)
  // ---------------------------------------------------------------------------
  wire h_sram   = t_req_i & ~t_addr_i[12];
  wire h_crc_r  = t_req_i &  t_addr_i[12];
  wire h_crc_wt = h_crc_r & (t_dir_i ? ~t_wready_o : ~t_rready_o);
  wire h_crc    = h_crc_r & ~h_crc_wt;             // accepted host access to the CRC block
  wire h_rd     = h_sram & ~t_dir_i;               // host SRAM read this clock
  wire h_wr     = h_sram &  t_dir_i;               // host SRAM write this clock

  // CRC-block access port: host first, else the core (core_creq is already 0 when h_crc = 1)
  wire        a_req   = h_crc | core_creq;
  wire        a_we    = h_crc ? t_dir_i   : core_cwe;
  wire [3:0]  a_off   = h_crc ? t_off     : core_coff;
  wire [15:0] a_wdata = h_crc ? t_wdata_i : core_cwdata;

  // Target read data select: 1 = CRC block, 0 = SRAM (every clock; used only after an accepted read)
  reg rsel_q;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) rsel_q <= 1'b0;
    else        rsel_q <= t_addr_i[12];

  assign t_rdata_o  = rsel_q ? crc_rdata_q : sram_dout;
  assign crc_idle_o = ~crc_busy;
  assign bs_valid_o = crc_outv;

  // ---------------------------------------------------------------------------
  // Instances
  // ---------------------------------------------------------------------------
  mc_core u_core (
    .clk         (clk),
    .rst_n       (rst_n),
    .mc_run_i    (mc_run_i),
    .wait_i      (wait_i),
    .mc_halt_o   (mc_halt_o),
    .mc_irq_o    (mc_irq_o),
    .dout_i      (sram_dout),
    .port_free_i (~h_sram),
    .h_rd_i      (h_rd),
    .h_wr_i      (h_wr),
    .h_addr_i    (t_addr_i[8:0]),
    .dreq_o      (core_dreq),
    .dwe_o       (core_dwe),
    .daddr_o     (core_daddr),
    .ddin_o      (core_ddin),
    .dbm_o       (core_dbm),
    .freq_o      (core_freq),
    .faddr_o     (core_faddr),
    .crc_busy_i  (crc_busy),
    .h_crc_i     (h_crc),
    .crc_rdata_i (crc_rdata_q),
    .creq_o      (core_creq),
    .cwe_o       (core_cwe),
    .coff_o      (core_coff),
    .cwdata_o    (core_cwdata),
    .m_req_o     (m_req_o),
    .m_dir_o     (m_dir_o),
    .m_addr_o    (m_addr_o),
    .m_wdata_o   (m_wdata_o),
    .m_wready_i  (m_wready_i),
    .m_rready_i  (m_rready_i),
    .m_rdata_i   (m_rdata_i)
  );

  sram_if u_sram (
    .clk     (clk),
    .h_req   (h_sram),
    .h_we    (t_dir_i),
    .h_addr  (t_addr_i[8:0]),
    .h_wdata (t_wdata_i),
    .d_req   (core_dreq),
    .d_we    (core_dwe),
    .d_addr  (core_daddr),
    .d_din   (core_ddin),
    .d_bm    (core_dbm),
    .f_req   (core_freq),
    .f_addr  (core_faddr),
    .dout    (sram_dout)
  );

  crc_bs u_crc (
    .clk     (clk),
    .rst_n   (rst_n),
    .a_req   (a_req),
    .a_we    (a_we),
    .a_off   (a_off),
    .a_wdata (a_wdata),
    .rdata_q (crc_rdata_q),
    .busy    (crc_busy),
    .outv    (crc_outv)
  );

endmodule
