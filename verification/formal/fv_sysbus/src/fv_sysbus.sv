// fv_sysbus: formal top for sysbus. Holds the clock/reset assumptions,
// instantiates the interface and e2e property modules, and is bound to every
// sysbus instance. Ports have the same names, widths and order as the RTL
// (all inputs here, as it only observes). Testplan: ../testplan/sysbus_fv_testplan.md

module fv_sysbus (
  // Clock and reset
  input  wire        clk,
  input  wire        rst_n,         // synchronised at chip level (G-02)

  // Master 0: host link (held until accepted, HL-04)
  input  wire        h_req_i,
  input  wire        h_dir_i,       // 1 = write, 0 = read
  input  wire [15:0] h_addr_i,
  input  wire [15:0] h_wdata_i,
  input  wire        h_wready_o,
  input  wire        h_rready_o,
  input  wire [15:0] h_rdata_o,     // valid in the clock after an accepted read

  // Master 1: main_ss master port (core, chip-bus addresses only)
  input  wire        m_req_i,
  input  wire        m_dir_i,       // 1 = write, 0 = read
  input  wire [15:0] m_addr_i,
  input  wire [15:0] m_wdata_i,
  input  wire        m_wready_o,
  input  wire        m_rready_o,
  input  wire [15:0] m_rdata_o,     // valid in the clock after an accepted read

  // Target: main_ss host-only port (SRAM 0x0000-0x01FF, CRC 0x1C10-0x1C1F)
  input  wire        t_req_o,
  input  wire        t_dir_o,
  input  wire [15:0] t_addr_o,
  input  wire [15:0] t_wdata_o,
  input  wire        t_wready_i,    // CRC busy wait (CRC-04)
  input  wire        t_rready_i,
  input  wire [15:0] t_rdata_i,

  // Bus targets: one-hot req, broadcast dir / addr / wdata, never wait
  input  wire        sys_req_o,     // sys_ctrl, 0x1C00-0x1C0F
  input  wire [3:0]  sc_req_o,      // sub-core n, 0x1000 + 0x80*n
  input  wire        pl_req_o,      // pin layer, 0x1800-0x181F
  input  wire        c_dir_o,
  input  wire [15:0] c_addr_o,
  input  wire [15:0] c_wdata_o,
  input  wire [15:0] sys_rdata_i,
  input  wire [63:0] sc_rdata_i,    // {SC3, SC2, SC1, SC0}
  input  wire [15:0] pl_rdata_i
);

  // ---------------------------------------------------------------------------
  // clk, rst_n
  // ---------------------------------------------------------------------------

  // 2001: clk is the only clock (G-01, Impl spec §7). No code: sby runs without
  // multiclock, so every state change is on the rising edge of clk.

  // First-clock flag: 1 only in the first clock of the trace
  logic fv_first_clk = 1'b1;
  always_ff @(posedge clk) fv_first_clk <= 1'b0;

  // rst_n is 0 in the first clock (G-02, Impl spec §3, §7)
  asm_2002_reset_in_first_clk: assume property(
    @(posedge clk)
      fv_first_clk -> !rst_n
  );

  // 2003: after the first clock rst_n is free (any clock, also while an access waits)
  // (G-02, Impl spec §7). No code: a free input already does this, and inputs only
  // change on clk edges.

  // ---------------------------------------------------------------------------
  // Property modules
  // ---------------------------------------------------------------------------

  // Host link (master 0) properties
  fv_sysbus_host_link_if u_fv_sysbus_host_link_if (.*);

  // Main_ss (master 1 and host-only target) properties
  fv_sysbus_main_ss_if u_fv_sysbus_main_ss_if (.*);

  // Bus target (sys_ctrl, sub-cores, pin layer) properties
  fv_sysbus_targets_if u_fv_sysbus_targets_if (.*);

  // Properties across the ports: routing, arbitration, read data
  fv_sysbus_e2e u_fv_sysbus_e2e (.*);

endmodule

// Attach to every sysbus; the RTL stays free of formal code
bind sysbus fv_sysbus u_fv_sysbus (.*);
