// fv_sysbus_e2e: properties of sysbus across its ports: routing from each master
// to its target (address map), host-first arbitration, wait forwarding, and data
// integrity in both directions, with read data in the clock after the accept (W+1).
// Testplan: ../testplan/sysbus_fv_testplan.md
// Note: yosys-slang takes boolean properties only, so "a |-> b" is written
// "a -> b" and "a |=> b" is written "$past(a) -> b".

module fv_sysbus_e2e (
  input logic        clk,
  input logic        rst_n,
  input logic        h_req_i,
  input logic        h_dir_i,
  input logic [15:0] h_addr_i,
  input logic [15:0] h_wdata_i,
  input logic        h_wready_o,
  input logic        h_rready_o,
  input logic [15:0] h_rdata_o,
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
  input logic [15:0] t_rdata_i,
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
  // Helper logic: address decode and bus-target owner
  // ---------------------------------------------------------------------------

  // Access accepted this clock: request and the ready of its direction
  logic fv_h_accept, fv_m_accept;
  assign fv_h_accept = h_req_i && (h_dir_i ? h_wready_o : h_rready_o);
  assign fv_m_accept = m_req_i && (m_dir_i ? m_wready_o : m_rready_o);

  // Address decode (Impl spec §3 address map): main_ss range = SRAM and CRC unit,
  // every other address is a bus-target address (unmapped included)
  logic fv_h_main_ss;
  assign fv_h_main_ss = (h_addr_i <= 16'h01FF) || (h_addr_i >= 16'h1C10 && h_addr_i <= 16'h1C1F);

  // Bus-target owner (Impl spec §5): the host if it requests a bus-target address,
  // otherwise the core if it requests, otherwise none
  logic        fv_h_owns, fv_m_owns, fv_own_dir;
  logic [15:0] fv_own_addr, fv_own_wdata;
  assign fv_h_owns    = h_req_i && !fv_h_main_ss;
  assign fv_m_owns    = m_req_i && !fv_h_owns;
  assign fv_own_dir   = fv_h_owns ? h_dir_i   : m_dir_i;
  assign fv_own_addr  = fv_h_owns ? h_addr_i  : m_addr_i;
  assign fv_own_wdata = fv_h_owns ? h_wdata_i : m_wdata_i;

  // Expected selects: the owner's address decoded with the address map
  logic       fv_owned, fv_exp_sys, fv_exp_pl;
  logic [3:0] fv_exp_sc;
  assign fv_owned   = fv_h_owns || fv_m_owns;
  assign fv_exp_sys = fv_owned && fv_own_addr >= 16'h1C00 && fv_own_addr <= 16'h1C0F;
  assign fv_exp_pl  = fv_owned && fv_own_addr >= 16'h1800 && fv_own_addr <= 16'h181F;
  assign fv_exp_sc  = {fv_owned && fv_own_addr >= 16'h1180 && fv_own_addr <= 16'h11FF,
                       fv_owned && fv_own_addr >= 16'h1100 && fv_own_addr <= 16'h117F,
                       fv_owned && fv_own_addr >= 16'h1080 && fv_own_addr <= 16'h10FF,
                       fv_owned && fv_own_addr >= 16'h1000 && fv_own_addr <= 16'h107F};

  // Any bus target selected this clock
  logic fv_any_sel;
  assign fv_any_sel = sys_req_o || (sc_req_o != 4'd0) || pl_req_o;

  // ---------------------------------------------------------------------------
  // Helper logic: bus target scoreboard
  // ---------------------------------------------------------------------------

  // Read accepted in the previous clock (W) and its address; not across a reset
  // (no read can be pending at reset)
  logic        fv_h_rd_q, fv_m_rd_q;
  logic [15:0] fv_h_addr_q, fv_m_addr_q;
  always_ff @(posedge clk) begin
    fv_h_rd_q   <= rst_n && fv_h_accept && !h_dir_i;
    fv_h_addr_q <= h_addr_i;
    fv_m_rd_q   <= rst_n && fv_m_accept && !m_dir_i;
    fv_m_addr_q <= m_addr_i;
  end

  // Read data R of the host read: the addressed target's read data in W+1
  // (2307, 2402, 2403, 2404), 0 for an unmapped address
  logic [15:0] fv_h_exp_rdata;
  always_comb begin
    fv_h_exp_rdata = 16'h0000;
    if (fv_h_addr_q <= 16'h01FF)                                    fv_h_exp_rdata = t_rdata_i;
    else if (fv_h_addr_q >= 16'h1000 && fv_h_addr_q <= 16'h107F)    fv_h_exp_rdata = sc_rdata_i[15:0];
    else if (fv_h_addr_q >= 16'h1080 && fv_h_addr_q <= 16'h10FF)    fv_h_exp_rdata = sc_rdata_i[31:16];
    else if (fv_h_addr_q >= 16'h1100 && fv_h_addr_q <= 16'h117F)    fv_h_exp_rdata = sc_rdata_i[47:32];
    else if (fv_h_addr_q >= 16'h1180 && fv_h_addr_q <= 16'h11FF)    fv_h_exp_rdata = sc_rdata_i[63:48];
    else if (fv_h_addr_q >= 16'h1800 && fv_h_addr_q <= 16'h181F)    fv_h_exp_rdata = pl_rdata_i;
    else if (fv_h_addr_q >= 16'h1C00 && fv_h_addr_q <= 16'h1C0F)    fv_h_exp_rdata = sys_rdata_i;
    else if (fv_h_addr_q >= 16'h1C10 && fv_h_addr_q <= 16'h1C1F)    fv_h_exp_rdata = t_rdata_i;
  end

  // Read data of the core read: same, but the core never addresses main_ss (2203)
  logic [15:0] fv_m_exp_rdata;
  always_comb begin
    fv_m_exp_rdata = 16'h0000;
    if (fv_m_addr_q >= 16'h1000 && fv_m_addr_q <= 16'h107F)         fv_m_exp_rdata = sc_rdata_i[15:0];
    else if (fv_m_addr_q >= 16'h1080 && fv_m_addr_q <= 16'h10FF)    fv_m_exp_rdata = sc_rdata_i[31:16];
    else if (fv_m_addr_q >= 16'h1100 && fv_m_addr_q <= 16'h117F)    fv_m_exp_rdata = sc_rdata_i[47:32];
    else if (fv_m_addr_q >= 16'h1180 && fv_m_addr_q <= 16'h11FF)    fv_m_exp_rdata = sc_rdata_i[63:48];
    else if (fv_m_addr_q >= 16'h1800 && fv_m_addr_q <= 16'h181F)    fv_m_exp_rdata = pl_rdata_i;
    else if (fv_m_addr_q >= 16'h1C00 && fv_m_addr_q <= 16'h1C0F)    fv_m_exp_rdata = sys_rdata_i;
  end

  // ---------------------------------------------------------------------------
  // Helper logic: two-copy check of the host ready outputs
  // ---------------------------------------------------------------------------

  // The ready outputs are combinational (Impl spec §3 port table), so the two copies
  // are two clocks of one trace with the same h_req_i, h_dir_i, h_addr_i and
  // t_*ready_i; h_wdata_i and the m_* inputs may differ between them.

  // Symbolic input values: any value, chosen at the start and then constant
  // (no reset, holds itself; read_slang ignores (* anyconst *))
  logic [19:0] fv_key;
  always_ff @(posedge clk) fv_key <= fv_key;

  logic fv_key_hit;
  assign fv_key_hit = {h_req_i, h_dir_i, h_addr_i, t_wready_i, t_rready_i} == fv_key;

  // First clock with these inputs: its ready outputs, and the m_* and h_wdata_i values
  // it had (these only for the covers)
  logic        fv_key_seen, fv_ref_wready, fv_ref_rready, fv_ref_m_req;
  logic [15:0] fv_ref_wdata;
  always_ff @(posedge clk)
    if (!rst_n) fv_key_seen <= 1'b0;
    else if (fv_key_hit && !fv_key_seen) begin
      fv_key_seen   <= 1'b1;
      fv_ref_wready <= h_wready_o;
      fv_ref_rready <= h_rready_o;
      fv_ref_m_req  <= m_req_i;
      fv_ref_wdata  <= h_wdata_i;
    end

  // Set once reset has been released (initialized, so a cover cannot be hit by the
  // arbitrary start values of the helper flops in the first clock)
  logic fv_rst_released = 1'b0;
  always_ff @(posedge clk) if (rst_n) fv_rst_released <= 1'b1;

  // ---------------------------------------------------------------------------
  // h_wready_o, h_rready_o
  // ---------------------------------------------------------------------------

  // The main_ss target's write wait is forwarded to the host (Impl spec §2, §3 port table, T2, B-3, CRC-04)
  ast_2501_wready_forwards_t_wready: assert property(
    @(posedge clk) disable iff (!rst_n)
      (h_req_i && h_dir_i && fv_h_main_ss) -> (h_wready_o == t_wready_i)
  );

  // h_wready_o does not change when only h_wdata_i or the m_* inputs change (Impl spec §3 port table, V3)
  ast_2502_wready_indep_of_wdata_core: assert property(
    @(posedge clk) disable iff (!rst_n)
      (fv_key_seen && fv_key_hit) -> (h_wready_o == fv_ref_wready)
  );

  // The main_ss target's read wait is forwarded to the host (Impl spec §2, §3 port table, T2, B-3, CRC-04)
  ast_2503_rready_forwards_t_rready: assert property(
    @(posedge clk) disable iff (!rst_n)
      (h_req_i && !h_dir_i && fv_h_main_ss) -> (h_rready_o == t_rready_i)
  );

  // h_rready_o does not change when only h_wdata_i or the m_* inputs change (Impl spec §3 port table, V3)
  ast_2504_rready_indep_of_wdata_core: assert property(
    @(posedge clk) disable iff (!rst_n)
      (fv_key_seen && fv_key_hit) -> (h_rready_o == fv_ref_rready)
  );

  // ---------------------------------------------------------------------------
  // h_rdata_o
  // ---------------------------------------------------------------------------

  // In the clock after an accepted host read, h_rdata_o = that read's data R
  // (Impl spec §3 port table, bus protocol, §6 T2, T3, BUS-02, D-BUS-4, D-BUS-7, B-1, V2)
  ast_2114_h_rdata_after_accept: assert property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_rd_q -> (h_rdata_o == fv_h_exp_rdata)
  );

  // ---------------------------------------------------------------------------
  // m_wready_o, m_rready_o
  // ---------------------------------------------------------------------------

  // m_wready_o = 0 exactly while the host requests a bus-target address (host first)
  // (Impl spec §2, §3 port table, §5, T1, T2, BUS-03, D-BUS-2, A-CHG-8, Main_ss spec §3.3, V3)
  ast_2505_m_wready_host_first: assert property(
    @(posedge clk) disable iff (!rst_n)
      m_wready_o == !(h_req_i && !fv_h_main_ss)
  );

  // The core is held at most one clock per host bus-target access (Impl spec §5, T1, B-2, D-BUS-2)
  ast_2506_m_wready_low_max_1_clk: assert property(
    @(posedge clk) disable iff (!rst_n)
      !$past(m_wready_o) -> m_wready_o
  );

  // m_rready_o = 0 exactly while the host requests a bus-target address (host first)
  // (Impl spec §2, §3 port table, §5, T1, T2, BUS-03, D-BUS-2, A-CHG-8, Main_ss spec §3.3, V3)
  ast_2507_m_rready_host_first: assert property(
    @(posedge clk) disable iff (!rst_n)
      m_rready_o == !(h_req_i && !fv_h_main_ss)
  );

  // The core is held at most one clock per host bus-target access (Impl spec §5, B-2, D-BUS-2)
  ast_2508_m_rready_low_max_1_clk: assert property(
    @(posedge clk) disable iff (!rst_n)
      !$past(m_rready_o) -> m_rready_o
  );

  // ---------------------------------------------------------------------------
  // m_rdata_o
  // ---------------------------------------------------------------------------

  // In the clock after an accepted core read, m_rdata_o = the addressed target's read data
  // (Impl spec §3 port table, bus protocol, §6 T1, T2, BUS-02, A-CHG-8, D-BUS-7, B-1, V2)
  ast_2509_m_rdata_after_accept: assert property(
    @(posedge clk) disable iff (!rst_n)
      fv_m_rd_q -> (m_rdata_o == fv_m_exp_rdata)
  );

  // ---------------------------------------------------------------------------
  // t_req_o, t_dir_o, t_addr_o, t_wdata_o
  // ---------------------------------------------------------------------------

  // t_req_o = 1 exactly while the host requests a main_ss address, never for the core
  // (Impl spec §2, §3 address map, D-BUS-5, D-MC-8, Main_ss spec §3.2, V1)
  ast_2510_t_req_host_main_ss_only: assert property(
    @(posedge clk) disable iff (!rst_n)
      t_req_o == (h_req_i && fv_h_main_ss)
  );

  // Target access direction = host direction (Impl spec §2, §3 port table, V2)
  ast_2511_t_dir_matches_host: assert property(
    @(posedge clk) disable iff (!rst_n)
      t_req_o -> (t_dir_o == h_dir_i)
  );

  // Target access address = host address, all 16 bits (Impl spec §2, §3 port table, Main_ss spec §3.2, V2)
  ast_2512_t_addr_matches_host: assert property(
    @(posedge clk) disable iff (!rst_n)
      t_req_o -> (t_addr_o == h_addr_i)
  );

  // Target write data = host write data (Impl spec §2, §3 port table, V2)
  ast_2513_t_wdata_matches_host: assert property(
    @(posedge clk) disable iff (!rst_n)
      (t_req_o && t_dir_o) -> (t_wdata_o == h_wdata_i)
  );

  // ---------------------------------------------------------------------------
  // sys_req_o, sc_req_o, pl_req_o
  // ---------------------------------------------------------------------------

  // sys_ctrl is selected exactly while the owner's address is in 0x1C00-0x1C0F
  // (Impl spec §2, §3 address map, §5, T2, BUS-03, BUS-04, D-BUS-6, Sys_ctrl spec §2.1 AS-1, V1, V2)
  ast_2514_sys_req_decode: assert property(
    @(posedge clk) disable iff (!rst_n)
      sys_req_o == fv_exp_sys
  );

  // Sub-core n is selected exactly while the owner's address is in 0x1000 + 0x80*n to 0x107F + 0x80*n
  // (Impl spec §2, §3 address map, §5, T1, T3, BUS-03, BUS-04, BUS-05, D-BUS-6, Subcore spec §3, V1, V2)
  ast_2515_sc_req_decode: assert property(
    @(posedge clk) disable iff (!rst_n)
      sc_req_o == fv_exp_sc
  );

  // The pin layer is selected exactly while the owner's address is in 0x1800-0x181F
  // (Impl spec §2, §3 address map, §5, T1, BUS-03, BUS-04, D-BUS-6, Pin_layer spec §3, V1, V2)
  ast_2516_pl_req_decode: assert property(
    @(posedge clk) disable iff (!rst_n)
      pl_req_o == fv_exp_pl
  );

  // ---------------------------------------------------------------------------
  // c_dir_o, c_addr_o, c_wdata_o
  // ---------------------------------------------------------------------------

  // Broadcast direction = the owner's direction (Impl spec §2, §3 port table, §5, D-BUS-9, V2)
  ast_2517_c_dir_matches_owner: assert property(
    @(posedge clk) disable iff (!rst_n)
      fv_any_sel -> (c_dir_o == fv_own_dir)
  );

  // Broadcast address = the owner's address, all 16 bits (Impl spec §2, §3 port table, §5, D-BUS-9, V1, V2)
  ast_2518_c_addr_matches_owner: assert property(
    @(posedge clk) disable iff (!rst_n)
      fv_any_sel -> (c_addr_o == fv_own_addr)
  );

  // Broadcast write data = the owner's write data (Impl spec §2, §3 port table, §5, T1, D-BUS-9, V2)
  ast_2519_c_wdata_matches_owner: assert property(
    @(posedge clk) disable iff (!rst_n)
      (fv_any_sel && c_dir_o) -> (c_wdata_o == fv_own_wdata)
  );

  // ---------------------------------------------------------------------------
  // Covers
  // ---------------------------------------------------------------------------

  // Host and core write a bus target in the same clock, the host wins (T1, BUS-03)
  cov_2505_host_core_same_clk: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_owns && h_dir_i && m_req_i && m_dir_i
  );

  // Host main_ss read and core sys_ctrl read accepted in the same clock, both checked in
  // the next clock with different data (T2, BUS-02)
  cov_2509_parallel_main_ss_and_target_rd: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_rd_q && fv_m_rd_q && fv_h_addr_q <= 16'h01FF && fv_m_addr_q == 16'h1C00 && t_rdata_i != sys_rdata_i
  );

  // The core is accepted while the host read waits for main_ss (T2, B-3)
  cov_2503_core_access_while_host_waits: cover property(
    @(posedge clk) disable iff (!rst_n)
      h_req_i && !h_dir_i && fv_h_main_ss && !h_rready_o && fv_m_accept
  );

  // The core is accepted while the host write waits for main_ss (B-3)
  cov_2501_core_access_while_host_wr_waits: cover property(
    @(posedge clk) disable iff (!rst_n)
      h_req_i && h_dir_i && fv_h_main_ss && !h_wready_o && fv_m_accept
  );

  // 2114 is checked on an SRAM read (Impl spec §3 address map)
  cov_2114_h_rd_sram: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_rd_q && fv_h_addr_q <= 16'h01FF && h_rdata_o != 16'h0000
  );

  // 2114 is checked on a CRC VAL read (T2)
  cov_2114_h_rd_crc: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_rd_q && fv_h_addr_q == 16'h1C14 && h_rdata_o != 16'h0000
  );

  // 2114 is checked on a sys_ctrl read (Impl spec §3 address map)
  cov_2114_h_rd_sys: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_rd_q && fv_h_addr_q == 16'h1C00 && h_rdata_o != 16'h0000
  );

  // 2114 is checked on a sub-core 3 read (slice order of sc_rdata_i)
  cov_2114_h_rd_sc3: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_rd_q && fv_h_addr_q == 16'h1180 && h_rdata_o != 16'h0000
  );

  // 2114 is checked on a pin layer read (Impl spec §3 address map)
  cov_2114_h_rd_pl: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_rd_q && fv_h_addr_q == 16'h1800 && h_rdata_o != 16'h0000
  );

  // 2114 is checked on an unmapped read (T3, B-1)
  cov_2114_h_rd_unmapped: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_rd_q && fv_h_addr_q == 16'h2000 && h_rdata_o == 16'h0000
  );

  // 2509 is checked on a sub-core 0 read (T1)
  cov_2509_m_rd_sc0: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_m_rd_q && fv_m_addr_q == 16'h1007 && m_rdata_o != 16'h0000
  );

  // 2509 is checked on a pin layer read (Impl spec §3 address map)
  cov_2509_m_rd_pl: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_m_rd_q && fv_m_addr_q == 16'h1800 && m_rdata_o != 16'h0000
  );

  // 2509 is checked on an unmapped read (B-1)
  cov_2509_m_rd_unmapped: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_m_rd_q && fv_m_addr_q == 16'h2000 && m_rdata_o == 16'h0000
  );

  // A core write to sub-core 0 is broadcast (T1)
  cov_2519_core_wr_broadcast: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_m_owns && sc_req_o[0] && c_dir_o && c_wdata_o != 16'h0000
  );

  // A host write to the pin layer is broadcast (T1)
  cov_2519_host_wr_broadcast: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_h_owns && pl_req_o && c_dir_o && c_wdata_o != 16'h0000
  );

  // 2502 is checked on a host write with another h_wdata_i and m_req_i (V3)
  cov_2502_same_inputs_other_wdata_core: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_key_seen && fv_key_hit && h_req_i && h_dir_i && h_wdata_i != fv_ref_wdata && m_req_i != fv_ref_m_req
  );

  // 2504 is checked on a host read with another m_req_i (V3)
  cov_2504_same_inputs_other_core: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_key_seen && fv_key_hit && h_req_i && !h_dir_i && m_req_i != fv_ref_m_req
  );

  // Reset is applied in the clock after an accepted host read (G-02, Impl spec §7)
  cov_2003_reset_with_rdata_due: cover property(
    @(posedge clk)
      !rst_n && fv_rst_released && fv_h_rd_q
  );

endmodule
