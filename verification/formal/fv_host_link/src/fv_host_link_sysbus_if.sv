// fv_host_link_sysbus_if: system bus (master 0) interface properties of host_link.
// Only clk, rst_n and the bus signals are used, so this file can also be used
// on the target side of the bus. Testplan: ../testplan/host_link_fv_testplan.md
// Note: yosys-slang takes boolean properties only, so "a |-> b" is written
// "a -> b" and "a |=> b" is written "$past(a) -> b".

module fv_host_link_sysbus_if (
  input logic        clk,
  input logic        rst_n,
  input logic        bus_req_o,
  input logic        bus_dir_o,
  input logic [15:0] bus_addr_o,
  input logic [15:0] bus_wdata_o,
  input logic        bus_wready_i,
  input logic        bus_rready_i,
  input logic [15:0] bus_rdata_i
);

  // ---------------------------------------------------------------------------
  // Helper logic
  // ---------------------------------------------------------------------------

  // Access accepted this clock: request and the ready of its direction
  logic fv_bus_accept, fv_bus_stall;
  assign fv_bus_accept = bus_req_o && (bus_dir_o ? bus_wready_i : bus_rready_i);
  assign fv_bus_stall  = bus_req_o && !fv_bus_accept;

  // Wait counters: consecutive clocks a write / read request waited (saturate at 8)
  logic [3:0] fv_wr_wait, fv_rd_wait;
  always_ff @(posedge clk) begin
    if (!rst_n || !(bus_req_o && bus_dir_o && !bus_wready_i)) fv_wr_wait <= '0;
    else if (fv_wr_wait < 4'd8) fv_wr_wait <= fv_wr_wait + 4'd1;

    if (!rst_n || !(bus_req_o && !bus_dir_o && !bus_rready_i)) fv_rd_wait <= '0;
    else if (fv_rd_wait < 4'd8) fv_rd_wait <= fv_rd_wait + 4'd1;
  end

  // Set once an access has been accepted (for the second-access cover)
  logic fv_acc_seen;
  always_ff @(posedge clk)
    if (!rst_n) fv_acc_seen <= 1'b0;
    else if (fv_bus_accept) fv_acc_seen <= 1'b1;

  // Set once reset has been released (initialized, so a cover cannot be hit by the
  // arbitrary start values of $past in the first clock)
  logic fv_rst_released = 1'b0;
  always_ff @(posedge clk) if (rst_n) fv_rst_released <= 1'b1;

  // ---------------------------------------------------------------------------
  // bus_wready_i, bus_rready_i, bus_rdata_i
  // ---------------------------------------------------------------------------

  // A write waits at most 8 clocks (CRC busy) (Sysbus spec bus protocol, BUS-02, BUS-06, D-HL-4, V4)
  asm_1201_wready_within_8_clks: assume property(
    @(posedge clk) disable iff (!rst_n)
      (bus_req_o && bus_dir_o && fv_wr_wait >= 4'd8) -> bus_wready_i
  );

  // A read waits at most 8 clocks (CRC busy) (Sysbus spec bus protocol, BUS-02, BUS-06, D-HL-4, V4)
  asm_1202_rready_within_8_clks: assume property(
    @(posedge clk) disable iff (!rst_n)
      (bus_req_o && !bus_dir_o && fv_rd_wait >= 4'd8) -> bus_rready_i
  );

  // Over-constraint: wready only while a write is requested; the spec allows it with
  // no request. Check as an assert on the bus target side, remove if it fails there (Sysbus spec bus protocol)
  asm_1221_wready_only_on_wr_req_oc: assume property(
    @(posedge clk) disable iff (!rst_n)
      !(bus_req_o && bus_dir_o) -> !bus_wready_i
  );

  // Over-constraint: rready only while a read is requested; the spec allows it with
  // no request. Check as an assert on the bus target side, remove if it fails there (Sysbus spec bus protocol)
  asm_1222_rready_only_on_rd_req_oc: assume property(
    @(posedge clk) disable iff (!rst_n)
      !(bus_req_o && !bus_dir_o) -> !bus_rready_i
  );

  // 1203: bus_rdata_i is free in every clock. No constraint is needed; the read
  // data R is sampled in the clock after the accept in fv_host_link_e2e.sv.

  // ---------------------------------------------------------------------------
  // bus_req_o
  // ---------------------------------------------------------------------------

  // No request in reset and in the first clock after reset release (D-HL-8, HL-07, V9)
  ast_1204_req_low_in_reset: assert property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> !bus_req_o
  );

  // A request that is not accepted stays up in the next clock (Impl spec §3 port table, Sysbus spec bus protocol, D-HL-7, HL-04)
  ast_1205_req_held_until_accept: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_bus_stall) -> bus_req_o
  );

  // A request drops in the clock after it is accepted (Impl spec §3 port table, T3, T4, D-HL-7, BUS-05)
  ast_1206_req_low_after_accept: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_bus_accept) -> !bus_req_o
  );

  // ---------------------------------------------------------------------------
  // bus_dir_o
  // ---------------------------------------------------------------------------

  // dir is 1 in reset and in the first clock after reset release (Impl spec §3 port table, D-HL-8)
  ast_1212_dir_high_in_reset: assert property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> bus_dir_o
  );

  // dir is stable while a request waits (Impl spec §3 port table, Sysbus spec bus protocol)
  ast_1213_dir_stable_while_stalled: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_bus_stall) -> $stable(bus_dir_o)
  );

  // ---------------------------------------------------------------------------
  // bus_addr_o
  // ---------------------------------------------------------------------------

  // addr is 0 in reset and in the first clock after reset release (Impl spec §3 port table, D-HL-8)
  ast_1215_addr_zero_in_reset: assert property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> (bus_addr_o == 16'h0000)
  );

  // addr is stable while a request waits (Impl spec §3 port table, Sysbus spec bus protocol, H-2)
  ast_1216_addr_stable_while_stalled: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_bus_stall) -> $stable(bus_addr_o)
  );

  // ---------------------------------------------------------------------------
  // bus_wdata_o
  // ---------------------------------------------------------------------------

  // wdata is 0 in reset and in the first clock after reset release (Impl spec §3 port table, D-HL-8)
  ast_1218_wdata_zero_in_reset: assert property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> (bus_wdata_o == 16'h0000)
  );

  // wdata is stable while a write waits (Impl spec §3 port table, Sysbus spec bus protocol, H-2)
  ast_1219_wdata_stable_while_stalled: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_bus_stall && bus_dir_o) -> $stable(bus_wdata_o)
  );

  // ---------------------------------------------------------------------------
  // Covers
  // ---------------------------------------------------------------------------

  // A read is accepted (Sysbus spec bus protocol, V2)
  cov_1202_rd_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      bus_req_o && !bus_dir_o && bus_rready_i
  );

  // A write is accepted (Sysbus spec bus protocol, V1)
  cov_1201_wr_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      bus_req_o && bus_dir_o && bus_wready_i
  );

  // A read waits the full 8 clocks (BUS-02, D-HL-4, V4)
  cov_1202_rd_wait_8_clks: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_rd_wait == 4'd8
  );

  // A write waits the full 8 clocks (BUS-02, D-HL-4, V4)
  cov_1201_wr_wait_8_clks: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_wr_wait == 4'd8
  );

  // A second access is accepted after the first one (A-CHG-2, HL-04, BUS-05)
  cov_1210_second_access: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_acc_seen && fv_bus_accept
  );

  // Reset is applied while a request is waiting (D-HL-8, G-02, V7)
  cov_1204_reset_while_req: cover property(
    @(posedge clk)
      !rst_n && fv_rst_released && $past(bus_req_o)
  );

endmodule
