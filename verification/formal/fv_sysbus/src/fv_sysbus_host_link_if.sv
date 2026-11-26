// fv_sysbus_host_link_if: host link (master 0) interface properties of sysbus.
// Only clk, rst_n and the h_* signals are used, so this file can also be used on
// the host-link side of the bus. Counterpart (assume/assert swapped):
// ../../fv_host_link/src/fv_host_link_sysbus_if.sv (bus_* there).
// Testplan: ../testplan/sysbus_fv_testplan.md
// Note: yosys-slang takes boolean properties only, so "a |-> b" is written
// "a -> b" and "a |=> b" is written "$past(a) -> b".

module fv_sysbus_host_link_if (
  input logic        clk,
  input logic        rst_n,
  input logic        h_req_i,
  input logic        h_dir_i,
  input logic [15:0] h_addr_i,
  input logic [15:0] h_wdata_i,
  input logic        h_wready_o,
  input logic        h_rready_o,
  input logic [15:0] h_rdata_o
);

  // ---------------------------------------------------------------------------
  // Helper logic
  // ---------------------------------------------------------------------------

  // Access accepted this clock: request and the ready of its direction
  logic fv_h_accept, fv_h_stall;
  assign fv_h_accept = h_req_i && (h_dir_i ? h_wready_o : h_rready_o);
  assign fv_h_stall  = h_req_i && !fv_h_accept;

  // Address decode (Impl spec §3 address map): main_ss range = SRAM and CRC unit,
  // every other address is a bus-target address (unmapped included)
  logic fv_h_main_ss;
  assign fv_h_main_ss = (h_addr_i <= 16'h01FF) || (h_addr_i >= 16'h1C10 && h_addr_i <= 16'h1C1F);

  // Wait counters: consecutive clocks a write / read request waited (saturate at 10)
  logic [3:0] fv_wr_wait, fv_rd_wait;
  always_ff @(posedge clk) begin
    if (!rst_n || !(h_req_i && h_dir_i && !h_wready_o)) fv_wr_wait <= '0;
    else if (fv_wr_wait < 4'd10) fv_wr_wait <= fv_wr_wait + 4'd1;

    if (!rst_n || !(h_req_i && !h_dir_i && !h_rready_o)) fv_rd_wait <= '0;
    else if (fv_rd_wait < 4'd10) fv_rd_wait <= fv_rd_wait + 4'd1;
  end

  // Set once an access has been accepted (for the second-access cover)
  logic fv_acc_seen;
  always_ff @(posedge clk)
    if (!rst_n) fv_acc_seen <= 1'b0;
    else if (fv_h_accept) fv_acc_seen <= 1'b1;

  // Set once reset has been released (initialized, so a cover cannot be hit by the
  // arbitrary start values of $past in the first clock)
  logic fv_rst_released = 1'b0;
  always_ff @(posedge clk) if (rst_n) fv_rst_released <= 1'b1;

  // ---------------------------------------------------------------------------
  // h_req_i
  // ---------------------------------------------------------------------------

  // No request in reset and in the first clock after reset release (Host_link spec §3, HL-07)
  asm_2101_req_low_in_reset: assume property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> !h_req_i
  );

  // A request that is not accepted stays up in the next clock (Impl spec §3 port table, bus protocol, HL-04)
  asm_2102_req_held_until_accept: assume property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_h_stall) -> h_req_i
  );

  // A request drops in the clock after it is accepted (Host_link spec §3, BUS-05)
  asm_2103_req_low_after_accept: assume property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_h_accept) -> !h_req_i
  );

  // ---------------------------------------------------------------------------
  // h_dir_i
  // ---------------------------------------------------------------------------

  // dir is 1 in reset and in the first clock after reset release (Host_link spec §3)
  asm_2104_dir_high_in_reset: assume property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> h_dir_i
  );

  // dir is stable while a request waits (Impl spec §3 bus protocol, requirements on neighbours)
  asm_2105_dir_stable_while_stalled: assume property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_h_stall) -> $stable(h_dir_i)
  );

  // ---------------------------------------------------------------------------
  // h_addr_i
  // ---------------------------------------------------------------------------

  // addr is 0 in reset and in the first clock after reset release (Host_link spec §3)
  asm_2106_addr_zero_in_reset: assume property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> (h_addr_i == 16'h0000)
  );

  // addr is stable while a request waits (Impl spec §3 bus protocol, requirements on neighbours)
  asm_2107_addr_stable_while_stalled: assume property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_h_stall) -> $stable(h_addr_i)
  );

  // ---------------------------------------------------------------------------
  // h_wdata_i
  // ---------------------------------------------------------------------------

  // wdata is 0 in reset and in the first clock after reset release (Host_link spec §3)
  asm_2108_wdata_zero_in_reset: assume property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> (h_wdata_i == 16'h0000)
  );

  // wdata is stable while a write waits (Impl spec §3 bus protocol, requirements on neighbours)
  asm_2109_wdata_stable_while_stalled: assume property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_h_stall && h_dir_i) -> $stable(h_wdata_i)
  );

  // ---------------------------------------------------------------------------
  // h_wready_o, h_rready_o
  // ---------------------------------------------------------------------------

  // A write waits at most 10 clocks (CRC busy: 8 bits + 2 stuff bits) (Impl spec bus protocol, BUS-02, BUS-06, B-3, Main_ss spec §8.4)
  ast_2110_wready_within_10_clks: assert property(
    @(posedge clk) disable iff (!rst_n)
      (h_req_i && h_dir_i && fv_wr_wait >= 4'd10) -> h_wready_o
  );

  // A write to a bus-target address is accepted in its first clock (Impl spec §2, §3 address map, §5, D-BUS-7, B-1)
  ast_2111_bus_target_wr_no_wait: assert property(
    @(posedge clk) disable iff (!rst_n)
      (h_req_i && h_dir_i && !fv_h_main_ss) -> h_wready_o
  );

  // A read waits at most 10 clocks (CRC busy: 8 bits + 2 stuff bits) (Impl spec bus protocol, BUS-02, BUS-06, B-3, Main_ss spec §8.4)
  ast_2112_rready_within_10_clks: assert property(
    @(posedge clk) disable iff (!rst_n)
      (h_req_i && !h_dir_i && fv_rd_wait >= 4'd10) -> h_rready_o
  );

  // A read of a bus-target address is accepted in its first clock (Impl spec §2, §3 address map, §5, T3, D-BUS-7, B-1)
  ast_2113_bus_target_rd_no_wait: assert property(
    @(posedge clk) disable iff (!rst_n)
      (h_req_i && !h_dir_i && !fv_h_main_ss) -> h_rready_o
  );

  // 2114 (h_rdata_o) needs the read data of the targets: see fv_sysbus_e2e.sv.

  // ---------------------------------------------------------------------------
  // Covers
  // ---------------------------------------------------------------------------

  // A write is accepted (Impl spec §3 bus protocol)
  cov_2110_wr_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      h_req_i && h_dir_i && h_wready_o
  );

  // A read is accepted (Impl spec §3 bus protocol)
  cov_2112_rd_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      h_req_i && !h_dir_i && h_rready_o
  );

  // A write waits the full 10 clocks (B-3, BUS-06)
  cov_2110_wr_wait_10_clks: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_wr_wait == 4'd10
  );

  // A read waits the full 10 clocks (B-3, BUS-06)
  cov_2112_rd_wait_10_clks: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_rd_wait == 4'd10
  );

  // A second access is accepted after the first one (HL-04, BUS-05)
  cov_2103_second_access: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_acc_seen && fv_h_accept
  );

  // Reset is applied while a request is waiting (G-02, Impl spec §7)
  cov_2003_reset_while_req_waits: cover property(
    @(posedge clk)
      !rst_n && fv_rst_released && $past(fv_h_stall)
  );

endmodule
