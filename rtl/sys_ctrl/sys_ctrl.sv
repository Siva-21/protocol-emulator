// -----------------------------------------------------------------------------
// sys_ctrl
//
// System control (pe_sys_ctrl): six registers at 0x1C00-0x1C05, the shared
// prescaler, run control of the main core and the sub-cores, the IRQ and
// doorbell flops and the WAIT vector. Never holds the bus (D-6).
//
// Implements docs/Implementation_spec/System_control_implementation_specification.pdf
// (v1.1, 10 Nov 2026), including A-CHG-3 (any master clears IRQ) and
// A-CHG-4 (SYS_CTRL and RUN_MASK read live state), with D-SYS-7..10 as
// written.
//
// Registers (0x1C00 + offset):
//   0x0 ID        R 0x5010; writes ignored
//   0x1 SYS_CTRL  W [0] run main core, [1] halt main core, [2] restart prescaler
//                 R [0] running, [1] halted                      reset 0x0002
//   0x2 RUN_MASK  W [3:0] run SCn, [7:4] halt SCn
//                 R [3:0] SCn running, [7:4] SCn halted          reset 0x00F0
//   0x3 IRQ       W [0] 1 = clear;  R [0] IRQ                    reset 0
//   0x4 DOORBELL  W [0] stored;     R [0] doorbell               reset 0
//   0x5 EVENTS    R WAIT vector; writes ignored
//   0x6-0xF       R 0; writes ignored
// A write that sets both run and halt for one target: halt wins (S-2).
//
// Bus target port: the same 7 signals as the host link's master port.
// wready = rready = 1, so an access is accepted in every clock with req = 1.
// A write takes effect at the edge ending that clock; a read has no side
// effect and its data is on rdata_o in the next clock. The interconnect
// raises req only for 0x1C00-0x1C0F (AS-1), so addr[15:4] and wdata[15:8]
// are unused.
//
// Structure (30 flops total, all async reset to 0):
//
//   req/dir/addr/wdata ──> sys_ctrl_ctrl (11) ──restart──> sys_ctrl_psc (15) ──> tick
//                            │ run_q/halt_q ──> sc_run, sc_halt
//                            │ mc_run, irq, db ──> mc_run, irq
//                            v
//   addr[3:0], status ──> sys_ctrl_rd (4) ──> rdata, wait
// -----------------------------------------------------------------------------

module sys_ctrl (
  input  wire        clk,
  input  wire        rst_n,          // synchronised reset (G-02)

  // Bus target, 0x1C00-0x1C0F: same 7 signals as the host link's master port
  input  wire        req_i,          // access to this block requested this clock (AS-1)
  input  wire        dir_i,          // 1 = write, 0 = read
  input  wire [15:0] addr_i,         // only [3:0] used
  input  wire [15:0] wdata_i,        // only [7:0] used
  output wire        wready_o,       // tied 1: never waits
  output wire        rready_o,       // tied 1: never waits
  output wire [15:0] rdata_o,        // valid the clock after the read is accepted

  // Main core
  output wire        mc_run_o,       // 1 = main core executes this clock
  input  wire        mc_halt_i,      // HALT instruction executes this clock
  input  wire        mc_irq_i,       // IRQ instruction executes this clock
  output wire [15:0] wait_o,         // WAIT vector, bit 15 = 0
  input  wire        crc_idle_i,

  // Sub-cores
  output wire [3:0]  sc_run_o,       // one-clock strobes, from flops
  output wire [3:0]  sc_halt_o,      // one-clock strobes, from flops
  output wire [2:0]  tick_o,         // [0] /16, [1] /256, [2] /4096, from flops
  input  wire [3:0]  sc_fa_space_i,  // FIFO A count < depth
  input  wire [3:0]  sc_fb_ne_i,     // FIFO B not empty
  input  wire [3:0]  sc_ntf_i,       // any notify flag set
  input  wire [3:0]  sc_halted_i,    // halted flop
  input  wire [3:0]  sc_err_i,       // any error flag set

  // Pin layer
  output wire        irq_o           // pad source 2, from a flop
);

  // The block never holds the bus (D-6)
  assign wready_o = 1'b1;
  assign rready_o = 1'b1;

  // Control -> prescaler / read side
  wire restart, irq, db;

  sys_ctrl_ctrl u_ctrl (
    .clk       (clk),
    .rst_n     (rst_n),
    .req_i     (req_i),
    .dir_i     (dir_i),
    .addr_i    (addr_i[3:0]),
    .wdata_i   (wdata_i[7:0]),
    .mc_halt_i (mc_halt_i),
    .mc_irq_i  (mc_irq_i),
    .mc_run_o  (mc_run_o),
    .sc_run_o  (sc_run_o),
    .sc_halt_o (sc_halt_o),
    .restart_o (restart),
    .irq_o     (irq),
    .db_o      (db)
  );

  sys_ctrl_psc u_psc (
    .clk       (clk),
    .rst_n     (rst_n),
    .restart_i (restart),
    .tick_o    (tick_o)
  );

  sys_ctrl_rd u_rd (
    .clk           (clk),
    .rst_n         (rst_n),
    .addr_i        (addr_i[3:0]),
    .mc_run_i      (mc_run_o),
    .irq_i         (irq),
    .db_i          (db),
    .sc_fa_space_i (sc_fa_space_i),
    .sc_fb_ne_i    (sc_fb_ne_i),
    .sc_ntf_i      (sc_ntf_i),
    .sc_halted_i   (sc_halted_i),
    .sc_err_i      (sc_err_i),
    .crc_idle_i    (crc_idle_i),
    .rdata_o       (rdata_o),
    .wait_o        (wait_o)
  );

  assign irq_o = irq;

endmodule
