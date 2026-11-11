// -----------------------------------------------------------------------------
// sys_ctrl_rd
//
// Read side of system control (spec §4, §5.5, §5.6).
//
//   off_q[3:0] : addr[3:0] of the previous clock, loaded every clock with no
//                enable (D-SYS-10). In the clock after an accepted read it
//                holds that read's offset, the only clock in which the
//                interconnect uses rdata_o; in every other clock rdata_o is
//                don't-care. All sources are levels without read side
//                effects, so reading one clock late is invisible to software.
//
//   Read mux (§5.6):
//     0 ID        0x5010 (M-2)
//     1 SYS_CTRL  {14'b0, !mc_run, mc_run}         reset 0x0002
//     2 RUN_MASK  {8'b0, sc_halted, ~sc_halted}    reset 0x00F0 (A-CHG-4)
//     3 IRQ       {15'b0, irq}
//     4 DOORBELL  {15'b0, db}
//     5 EVENTS    WAIT vector
//     6-F unused  0
//
//   WAIT vector (§5.5, SYS-05, D-4): combinational, no flop, so WAIT wakes
//   in the same clock as mc.py's live events(). Bit 14 (S-1) is any sub-core
//   halted or with an error flag; bit 15 = 0.
//
// Flops: 4 (off_q).
// -----------------------------------------------------------------------------

module sys_ctrl_rd (
  input  wire        clk,
  input  wire        rst_n,

  input  wire [3:0]  addr_i,         // offset of this clock's access

  // Register state, from sys_ctrl_ctrl
  input  wire        mc_run_i,
  input  wire        irq_i,
  input  wire        db_i,

  // Status, from the sub-cores and the main core
  input  wire [3:0]  sc_fa_space_i,  // FIFO A count < depth
  input  wire [3:0]  sc_fb_ne_i,     // FIFO B not empty
  input  wire [3:0]  sc_ntf_i,       // any notify flag set
  input  wire [3:0]  sc_halted_i,    // halted flop
  input  wire [3:0]  sc_err_i,       // any error flag set
  input  wire        crc_idle_i,

  output wire [15:0] rdata_o,        // valid the clock after the read is accepted
  output wire [15:0] wait_o          // WAIT vector, bit 15 = 0
);

  localparam [15:0] ID = 16'h5010;   // M-2

  logic [3:0] off_q;  // offset of the previous clock

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) off_q <= 4'd0;
    else        off_q <= addr_i;
  end

  // ---------------------------------------------------------------------------
  // WAIT vector (§5.5)
  // ---------------------------------------------------------------------------
  assign wait_o = {1'b0,                          // [15]
                   |(sc_halted_i | sc_err_i),     // [14]
                   crc_idle_i,                    // [13]
                   db_i,                          // [12]
                   sc_ntf_i,                      // [11:8]
                   sc_fb_ne_i,                    // [7:4]
                   sc_fa_space_i};                // [3:0]

  // ---------------------------------------------------------------------------
  // Read mux (§5.6)
  // ---------------------------------------------------------------------------
  assign rdata_o = (off_q == 4'd0) ? ID                               :
                   (off_q == 4'd1) ? {14'd0, ~mc_run_i, mc_run_i}     :
                   (off_q == 4'd2) ? {8'd0, sc_halted_i, ~sc_halted_i} :
                   (off_q == 4'd3) ? {15'd0, irq_i}                   :
                   (off_q == 4'd4) ? {15'd0, db_i}                    :
                   (off_q == 4'd5) ? wait_o                           :
                                     16'd0;

endmodule
