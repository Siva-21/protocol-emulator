// -----------------------------------------------------------------------------
// sys_ctrl_psc
//
// Shared prescaler (spec §5.1, SYS-03, D-1, D-2).
//   - cnt[11:0] free-runs from reset and is never stopped; only a restart
//     (SYS_CTRL[2] write) changes its phase.
//   - tick[0] = 1 in exactly the clocks where cnt[3:0]  = 0  (/16)
//     tick[1] = 1 in exactly the clocks where cnt[7:0]  = 0  (/256)
//     tick[2] = 1 in exactly the clocks where cnt[11:0] = 0  (/4096)
//     taken from flops (D-1), not from a decode of cnt.
//   - Restart in clock W: cnt = 0 and all three ticks = 1 in W + 1 (D-2).
//   - First clock after reset: cnt = 0 but tick = 0. Harmless, no timer runs.
//
// The /1 tap is not sent; a timer with PSC = 0 uses constant 1 (SC-TMR-01).
// Flops: 15 (cnt 12, tick 3).
// -----------------------------------------------------------------------------

module sys_ctrl_psc (
  input  wire       clk,
  input  wire       rst_n,

  input  wire       restart_i,  // SYS_CTRL[2] write, from sys_ctrl_ctrl
  output wire [2:0] tick_o      // [0] /16, [1] /256, [2] /4096
);

  logic [11:0] cnt;   // prescaler counter
  logic [2:0]  tick;  // registered ticks

  // Group carries of the incrementer: cnt + 1 wraps the group to 0
  wire c4  = &cnt[3:0];
  wire c8  = c4 & (&cnt[7:4]);
  wire c12 = c8 & (&cnt[11:8]);

  wire [11:0] cnt_d  = restart_i ? 12'd0 : cnt + 12'd1;
  wire [2:0]  tick_d = {restart_i | c12, restart_i | c8, restart_i | c4};

  // All reset to 0 (G-02)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt  <= 12'd0;
      tick <= 3'd0;
    end else begin
      cnt  <= cnt_d;
      tick <= tick_d;
    end
  end

  assign tick_o = tick;

endmodule
