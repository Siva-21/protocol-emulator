// fv_sysbus_targets_if: bus-target interface properties of sysbus (sys_ctrl,
// sub-cores 0-3, pin layer: one-hot req, broadcast dir / addr / wdata, read
// data in W+1). Only clk, rst_n and the bus-target signals are used, so this
// file can also be used on the target side of the bus.
// Testplan: ../testplan/sysbus_fv_testplan.md
// Note: yosys-slang takes boolean properties only, so "a |-> b" is written
// "a -> b" and "a |=> b" is written "$past(a) -> b".

module fv_sysbus_targets_if (
  input logic        clk,
  input logic        rst_n,
  input logic        sys_req_o,
  input logic [3:0]  sc_req_o,
  input logic        pl_req_o,
  input logic        c_dir_o,
  input logic [15:0] c_addr_o,
  input logic [15:0] c_wdata_o,
  input logic [15:0] sys_rdata_i,
  input logic [63:0] sc_rdata_i,
  input logic [15:0] pl_rdata_i
);

  // ---------------------------------------------------------------------------
  // Helper logic
  // ---------------------------------------------------------------------------

  // All selects in one vector
  logic [5:0] fv_sel;
  assign fv_sel = {sys_req_o, sc_req_o, pl_req_o};

  // ---------------------------------------------------------------------------
  // sys_req_o, sc_req_o, pl_req_o
  // ---------------------------------------------------------------------------

  // At most one target is selected in a clock: clearing the lowest 1 leaves 0 (Impl spec §3 port table, §4.2 text, AS-1)
  ast_2401_select_onehot0: assert property(
    @(posedge clk) disable iff (!rst_n)
      (fv_sel & (fv_sel - 6'd1)) == 6'd0
  );

  // ---------------------------------------------------------------------------
  // sys_rdata_i, sc_rdata_i, pl_rdata_i
  // ---------------------------------------------------------------------------

  // 2402, 2403, 2404: sys_rdata_i, sc_rdata_i and pl_rdata_i are free in every clock.
  // No constraint is needed; the read data is sampled in the clock after the read in
  // fv_sysbus_e2e.sv.

  // ---------------------------------------------------------------------------
  // Covers
  // ---------------------------------------------------------------------------

  // sys_ctrl is written (T2)
  cov_2514_sys_wr: cover property(
    @(posedge clk) disable iff (!rst_n)
      sys_req_o && c_dir_o
  );

  // sys_ctrl is read (T2)
  cov_2514_sys_rd: cover property(
    @(posedge clk) disable iff (!rst_n)
      sys_req_o && !c_dir_o
  );

  // Sub-core 0 is written (T1)
  cov_2515_sc0_wr: cover property(
    @(posedge clk) disable iff (!rst_n)
      sc_req_o[0] && c_dir_o
  );

  // Sub-core 0 is read (T1)
  cov_2515_sc0_rd: cover property(
    @(posedge clk) disable iff (!rst_n)
      sc_req_o[0] && !c_dir_o
  );

  // Sub-core 1 is selected (T3)
  cov_2515_sc1_sel: cover property(
    @(posedge clk) disable iff (!rst_n)
      sc_req_o[1]
  );

  // Sub-core 2 is selected (Impl spec §3 address map)
  cov_2515_sc2_sel: cover property(
    @(posedge clk) disable iff (!rst_n)
      sc_req_o[2]
  );

  // Sub-core 3 is selected (Impl spec §3 address map)
  cov_2515_sc3_sel: cover property(
    @(posedge clk) disable iff (!rst_n)
      sc_req_o[3]
  );

  // The pin layer is written (T1)
  cov_2516_pl_wr: cover property(
    @(posedge clk) disable iff (!rst_n)
      pl_req_o && c_dir_o
  );

  // The pin layer is read (Impl spec §3 address map)
  cov_2516_pl_rd: cover property(
    @(posedge clk) disable iff (!rst_n)
      pl_req_o && !c_dir_o
  );

endmodule
