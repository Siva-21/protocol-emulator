// -----------------------------------------------------------------------------
// sys_ctrl_ctrl
//
// Write decode and run/IRQ/doorbell state of system control (spec §4,
// §5.2-§5.4). No state machine: every flop group is one equation.
//
//   Decode (§4): wr = req & dir (wready = 1, so every requested write is
//     accepted). Offsets 1 SYS_CTRL, 2 RUN_MASK, 3 IRQ, 4 DOORBELL; other
//     offsets ignore writes.
//
//   Sub-core run control (§5.2, SYS-02, S-2, D-3): one-clock strobes in the
//     clock after a RUN_MASK write. Run + halt for one n gives halt only.
//
//   Main-core run flop (§5.3, MC-05, S-2, D-5, D-SYS-7/8/9): SYS_CTRL acts on
//     mc_run directly (no strobe flops), so the main core starts in W + 1.
//     Halt wins over run, including the HALT instruction in the same clock.
//     Stored with run polarity: reset 0 = halted (SYS-01).
//
//   IRQ and doorbell (§5.4, SYS-04, A-CHG-3, S-4a, S-4c): IRQ is set by the
//     IRQ instruction and cleared by a write of 1 from any master; set wins.
//     DOORBELL bit 0 takes the written value from any master.
//
// Flops: 11 (run_q 4, halt_q 4, mc_run 1, irq 1, db 1).
// -----------------------------------------------------------------------------

module sys_ctrl_ctrl (
  input  wire       clk,
  input  wire       rst_n,

  // Bus target (wready = rready = 1, tied off in the top level)
  input  wire       req_i,
  input  wire       dir_i,       // 1 = write, 0 = read
  input  wire [3:0] addr_i,      // offset; addr[15:4] decoded by the interconnect (AS-1)
  input  wire [7:0] wdata_i,     // wdata[15:8] unused

  // Main core
  input  wire       mc_halt_i,   // HALT instruction executes this clock
  input  wire       mc_irq_i,    // IRQ instruction executes this clock
  output wire       mc_run_o,

  // Sub-cores
  output wire [3:0] sc_run_o,    // one-clock strobes
  output wire [3:0] sc_halt_o,   // one-clock strobes

  // To sys_ctrl_psc
  output wire       restart_o,   // SYS_CTRL[2] write

  // State, to sys_ctrl_rd and the pin layer
  output wire       irq_o,
  output wire       db_o
);

  logic [3:0] run_q;   // sub-core run strobes
  logic [3:0] halt_q;  // sub-core halt strobes
  logic       mc_run;  // main core running
  logic       irq;     // host IRQ
  logic       db;      // doorbell

  // ---------------------------------------------------------------------------
  // Decode (§4)
  // ---------------------------------------------------------------------------
  wire wr     = req_i & dir_i;
  wire wr_sys = wr & (addr_i == 4'd1);
  wire wr_rm  = wr & (addr_i == 4'd2);
  wire wr_irq = wr & (addr_i == 4'd3);
  wire wr_db  = wr & (addr_i == 4'd4);

  assign restart_o = wr_sys & wdata_i[2];

  // ---------------------------------------------------------------------------
  // Sub-core run control (§5.2): halt wins
  // ---------------------------------------------------------------------------
  wire [3:0] run_q_d  = {4{wr_rm}} & wdata_i[3:0] & ~wdata_i[7:4];
  wire [3:0] halt_q_d = {4{wr_rm}} & wdata_i[7:4];

  // ---------------------------------------------------------------------------
  // Main-core run flop (§5.3): clear wins
  // ---------------------------------------------------------------------------
  wire mc_set   = wr_sys & wdata_i[0];
  wire mc_clr   = (wr_sys & wdata_i[1]) | mc_halt_i;
  wire mc_run_d = mc_clr ? 1'b0 : (mc_set ? 1'b1 : mc_run);

  // ---------------------------------------------------------------------------
  // IRQ and doorbell (§5.4): IRQ set wins
  // ---------------------------------------------------------------------------
  wire irq_d = mc_irq_i | (irq & ~(wr_irq & wdata_i[0]));
  wire db_d  = wr_db ? wdata_i[0] : db;

  // ---------------------------------------------------------------------------
  // Registers: all reset to 0 (G-02, SYS-01)
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      run_q  <= 4'd0;
      halt_q <= 4'd0;
      mc_run <= 1'b0;
      irq    <= 1'b0;
      db     <= 1'b0;
    end else begin
      run_q  <= run_q_d;
      halt_q <= halt_q_d;
      mc_run <= mc_run_d;
      irq    <= irq_d;
      db     <= db_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Outputs
  // ---------------------------------------------------------------------------
  assign sc_run_o  = run_q;
  assign sc_halt_o = halt_q;
  assign mc_run_o  = mc_run;
  assign irq_o     = irq;
  assign db_o      = db;

endmodule
