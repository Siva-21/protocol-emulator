// fv_sysbus_main_ss_if: main_ss interface properties of sysbus, both ports: m_*
// (master 1, main core) and t_* (host-only target: SRAM 0x0000-0x01FF, CRC unit
// 0x1C10-0x1C1F). Only clk, rst_n and the m_* and t_* signals are used, so this
// file can also be used on the main_ss side of the bus.
// Testplan: ../testplan/sysbus_fv_testplan.md
// Note: yosys-slang takes boolean properties only, so "a |-> b" is written
// "a -> b" and "a |=> b" is written "$past(a) -> b".

module fv_sysbus_main_ss_if (
  input logic        clk,
  input logic        rst_n,
  input logic        m_req_i,
  input logic        m_dir_i,
  input logic [15:0] m_addr_i,
  input logic [15:0] m_wdata_i,
  input logic        m_wready_o,
  input logic        m_rready_o,
  input logic [15:0] m_rdata_o,
  input logic        t_req_o,
  input logic        t_dir_o,
  input logic [15:0] t_addr_o,
  input logic [15:0] t_wdata_o,
  input logic        t_wready_i,
  input logic        t_rready_i,
  input logic [15:0] t_rdata_i
);

  // ---------------------------------------------------------------------------
  // Helper logic
  // ---------------------------------------------------------------------------

  // Core access accepted this clock: request and the ready of its direction
  logic fv_m_accept, fv_m_stall;
  assign fv_m_accept = m_req_i && (m_dir_i ? m_wready_o : m_rready_o);
  assign fv_m_stall  = m_req_i && !fv_m_accept;

  // Target access accepted this clock: request and the ready of its direction
  logic fv_t_accept, fv_t_stall;
  assign fv_t_accept = t_req_o && (t_dir_o ? t_wready_i : t_rready_i);
  assign fv_t_stall  = t_req_o && !fv_t_accept;

  // Address decode (Impl spec §3 address map): main_ss range = SRAM and CRC unit
  logic fv_m_main_ss;
  assign fv_m_main_ss = (m_addr_i <= 16'h01FF) || (m_addr_i >= 16'h1C10 && m_addr_i <= 16'h1C1F);

  // Wait counters: consecutive clocks a target write / read waited (saturate at 10)
  logic [3:0] fv_t_wr_wait, fv_t_rd_wait;
  always_ff @(posedge clk) begin
    if (!rst_n || !(t_req_o && t_dir_o && !t_wready_i)) fv_t_wr_wait <= '0;
    else if (fv_t_wr_wait < 4'd10) fv_t_wr_wait <= fv_t_wr_wait + 4'd1;

    if (!rst_n || !(t_req_o && !t_dir_o && !t_rready_i)) fv_t_rd_wait <= '0;
    else if (fv_t_rd_wait < 4'd10) fv_t_rd_wait <= fv_t_rd_wait + 4'd1;
  end

  // ---------------------------------------------------------------------------
  // m_req_i, m_dir_i
  // ---------------------------------------------------------------------------

  // m_req_i is a free input (no property in the testplan).

  // dir is stable while a core request waits (Impl spec §3 bus protocol, Main_ss spec §3.1)
  asm_2201_m_dir_stable_while_stalled: assume property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_m_stall) -> $stable(m_dir_i)
  );

  // ---------------------------------------------------------------------------
  // m_addr_i
  // ---------------------------------------------------------------------------

  // addr is stable while a core request waits (Impl spec §3 bus protocol, Main_ss spec §3.1)
  asm_2202_m_addr_stable_while_stalled: assume property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_m_stall) -> $stable(m_addr_i)
  );

  // The core requests bus-target addresses only, never SRAM or the CRC unit
  // (Impl spec §2, §3 requirements on neighbours, D-MC-8)
  asm_2203_m_addr_not_main_ss: assume property(
    @(posedge clk) disable iff (!rst_n)
      m_req_i -> !fv_m_main_ss
  );

  // ---------------------------------------------------------------------------
  // m_wdata_i
  // ---------------------------------------------------------------------------

  // wdata is stable while a core write waits (Impl spec §3 bus protocol, Main_ss spec §3.1)
  asm_2204_m_wdata_stable_while_stalled: assume property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_m_stall && m_dir_i) -> $stable(m_wdata_i)
  );

  // ---------------------------------------------------------------------------
  // t_req_o
  // ---------------------------------------------------------------------------

  // A target request that is not accepted stays up in the next clock (Impl spec §3 bus protocol, Main_ss spec §3.1)
  ast_2301_t_req_held_until_accept: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_t_stall) -> t_req_o
  );

  // ---------------------------------------------------------------------------
  // t_dir_o, t_addr_o, t_wdata_o
  // ---------------------------------------------------------------------------

  // dir is stable while a target request waits (Impl spec §3 bus protocol, Main_ss spec §3.1)
  ast_2302_t_dir_stable_while_stalled: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_t_stall) -> $stable(t_dir_o)
  );

  // addr is stable while a target request waits (Impl spec §3 bus protocol, Main_ss spec §3.1)
  ast_2303_t_addr_stable_while_stalled: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_t_stall) -> $stable(t_addr_o)
  );

  // wdata is stable while a target write waits (Impl spec §3 bus protocol, Main_ss spec §3.1)
  ast_2304_t_wdata_stable_while_stalled: assert property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_t_stall && t_dir_o) -> $stable(t_wdata_o)
  );

  // ---------------------------------------------------------------------------
  // t_wready_i, t_rready_i, t_rdata_i
  // ---------------------------------------------------------------------------

  // 2305, 2306: t_wready_i and t_rready_i do not depend on t_req_o in the same clock
  // (Impl spec §3 port table, requirements on neighbours, Main_ss spec §3.2). No code:
  // both are free inputs, which covers every independent ready behaviour.

  // A target write waits at most 10 clocks (CRC busy: 8 bits + 2 stuff bits)
  // (Impl spec §3 port table, B-3, BUS-06, CRC-03, CRC-04, Main_ss spec §3.2, §8.4)
  asm_2308_t_wready_within_10_clks: assume property(
    @(posedge clk) disable iff (!rst_n)
      (t_req_o && t_dir_o && fv_t_wr_wait >= 4'd10) -> t_wready_i
  );

  // A target read waits at most 10 clocks (CRC busy: 8 bits + 2 stuff bits)
  // (Impl spec §3 port table, B-3, BUS-06, CRC-03, CRC-04, Main_ss spec §3.2, §8.4)
  asm_2309_t_rready_within_10_clks: assume property(
    @(posedge clk) disable iff (!rst_n)
      (t_req_o && !t_dir_o && fv_t_rd_wait >= 4'd10) -> t_rready_i
  );

  // 2307: t_rdata_i is free in every clock. No constraint is needed; the read data
  // is sampled in the clock after the accept in fv_sysbus_e2e.sv.

  // ---------------------------------------------------------------------------
  // Covers
  // ---------------------------------------------------------------------------

  // A core write is accepted (Impl spec §3 bus protocol, T1)
  cov_2505_core_wr_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      m_req_i && m_dir_i && m_wready_o
  );

  // A core read is accepted (Impl spec §3 bus protocol, T1)
  cov_2507_core_rd_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      m_req_i && !m_dir_i && m_rready_o
  );

  // A core write is held one clock, then accepted (Impl spec §5, T1, B-2)
  cov_2506_core_wr_held_then_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_m_stall && m_dir_i) && fv_m_accept && m_dir_i
  );

  // A core read is held one clock, then accepted (Impl spec §5, B-2)
  cov_2508_core_rd_held_then_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      $past(fv_m_stall && !m_dir_i) && fv_m_accept && !m_dir_i
  );

  // Back-to-back core accesses: accepted in two consecutive clocks (T1)
  cov_2507_core_back_to_back: cover property(
    @(posedge clk) disable iff (!rst_n)
      $past(rst_n && fv_m_accept) && fv_m_accept
  );

  // A target write is accepted (Impl spec §3 bus protocol)
  cov_2308_t_wr_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      t_req_o && t_dir_o && t_wready_i
  );

  // A target read is accepted (Impl spec §3 bus protocol, T2)
  cov_2309_t_rd_accept: cover property(
    @(posedge clk) disable iff (!rst_n)
      t_req_o && !t_dir_o && t_rready_i
  );

  // A target write waits the full 10 clocks (B-3, BUS-06, CRC-04)
  cov_2308_t_wr_wait_10_clks: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_t_wr_wait == 4'd10
  );

  // A target read waits the full 10 clocks (T2, B-3, BUS-06, CRC-04)
  cov_2309_t_rd_wait_10_clks: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_t_rd_wait == 4'd10
  );

endmodule
