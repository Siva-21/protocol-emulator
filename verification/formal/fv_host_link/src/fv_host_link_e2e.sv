// fv_host_link_e2e: properties of host_link that use both the host (SPI) and
// the system bus interface: request timing, one access per frame, and data
// integrity from the SPI frame to the bus and back.
// Testplan: ../testplan/host_link_fv_testplan.md
// Note: yosys-slang takes boolean properties only, so "a |-> b" is written
// "a -> b" and "a |-> ##3 b" is written "$past(a, 3) -> b".

module fv_host_link_e2e (
  input logic        clk,
  input logic        rst_n,
  input logic        spi_sck_i,
  input logic        spi_csn_i,
  input logic        spi_mosi_i,
  input logic        spi_miso_o,
  input logic        bus_req_o,
  input logic        bus_dir_o,
  input logic [15:0] bus_addr_o,
  input logic [15:0] bus_wdata_o,
  input logic        bus_wready_i,
  input logic        bus_rready_i,
  input logic [15:0] bus_rdata_i
);

  // ---------------------------------------------------------------------------
  // Helper logic: SPI host frame model
  // ---------------------------------------------------------------------------

  // SCK rise inside a frame (CS_n low)
  logic fv_sck_q = 1'b0;
  always_ff @(posedge clk) fv_sck_q <= spi_sck_i;

  logic fv_frame_rise;
  assign fv_frame_rise = spi_sck_i && !fv_sck_q && !spi_csn_i;

  // Frame bits: fv_bit_cnt = SCK rises seen in this frame (0..40, cleared by CS_n high);
  // MOSI of frame bit k is stored in fv_bits[40-k], so frame bit 1 is fv_bits[39]
  logic [5:0]  fv_bit_cnt;
  logic [39:0] fv_bits;
  always_ff @(posedge clk)
    if (!rst_n || spi_csn_i) fv_bit_cnt <= '0;
    else if (fv_frame_rise && fv_bit_cnt < 6'd40) begin
      fv_bit_cnt                 <= fv_bit_cnt + 6'd1;
      fv_bits[6'd39 - fv_bit_cnt] <= spi_mosi_i;
    end

  // Frame fields (Impl spec §3): A[7:0] = bits 1-8, A[15:8] = bits 9-16,
  // R/W = bit 17, D[7:0] = bits 25-32, D[15:8] = bits 33-40, each byte MSB first
  logic [15:0] fv_frame_addr;
  logic        fv_frame_read;
  assign fv_frame_addr = {fv_bits[31:24], fv_bits[39:32]};
  assign fv_frame_read = fv_bits[23];

  // Issue points: 17th rise with MOSI = 1 (read), 40th rise of a write frame,
  // and any rise after bit 40
  logic fv_rd_rise17, fv_wr_rise40, fv_rise_after40;
  assign fv_rd_rise17    = fv_frame_rise && fv_bit_cnt == 6'd16 && spi_mosi_i;
  assign fv_wr_rise40    = fv_frame_rise && fv_bit_cnt == 6'd39 && !fv_frame_read;
  assign fv_rise_after40 = fv_frame_rise && fv_bit_cnt == 6'd40;

  // Clocks since reset release (saturates at 3), to skip checks across a reset
  logic [1:0] fv_clks_out_of_rst;
  always_ff @(posedge clk)
    if (!rst_n) fv_clks_out_of_rst <= '0;
    else if (fv_clks_out_of_rst < 2'd3) fv_clks_out_of_rst <= fv_clks_out_of_rst + 2'd1;

  // ---------------------------------------------------------------------------
  // Helper logic: bus target scoreboard
  // ---------------------------------------------------------------------------

  // Access accepted this clock: request and the ready of its direction
  logic fv_bus_accept;
  assign fv_bus_accept = bus_req_o && (bus_dir_o ? bus_wready_i : bus_rready_i);

  // Expected access, latched at its issue point. At the 40th rise, bit 40 is
  // still on MOSI, so D[15:8] = {bits 33-39, MOSI}.
  logic        fv_exp_dir;
  logic [15:0] fv_exp_addr, fv_exp_wdata;
  always_ff @(posedge clk)
    if (fv_rd_rise17) begin
      fv_exp_dir  <= 1'b0;
      fv_exp_addr <= fv_frame_addr;
    end else if (fv_wr_rise40) begin
      fv_exp_dir   <= 1'b1;
      fv_exp_addr  <= fv_frame_addr;
      fv_exp_wdata <= {fv_bits[7:1], spi_mosi_i, fv_bits[15:8]};
    end

  // One access owed per issue point: set at the issue, cleared at the accept
  logic fv_acc_owed;
  always_ff @(posedge clk)
    if (!rst_n) fv_acc_owed <= 1'b0;
    else if (fv_rd_rise17 || fv_wr_rise40) fv_acc_owed <= 1'b1;
    else if (fv_bus_accept) fv_acc_owed <= 1'b0;

  // Symbolic bit index: any value 0..15, chosen at the start and then constant
  // (no reset, holds itself; read_slang ignores (* anyconst *))
  logic [3:0] fv_idx;
  always_ff @(posedge clk) fv_idx <= fv_idx;

  // R in MISO order: frame bit k (25..40) carries bit 40-k of {R[7:0], R[15:8]}
  logic [15:0] fv_rdata_in_spi;
  assign fv_rdata_in_spi = {bus_rdata_i[7:0], bus_rdata_i[15:8]};

  // Read data bit under check: bit fv_idx of R in MISO order, sampled in the
  // clock after the read accept (1203, W+1)
  logic fv_rd_accept_q, fv_rbit;
  always_ff @(posedge clk) begin
    fv_rd_accept_q <= rst_n && fv_bus_accept && !bus_dir_o;
    if (fv_rd_accept_q) fv_rbit <= fv_rdata_in_spi[fv_idx];
  end

  // For the covers: clocks the current read request has waited (saturates at 8), and
  // whether the read of this frame was accepted only after the full 8-clock wait
  logic [3:0] fv_rd_wait;
  logic       fv_rd_max_wait;
  always_ff @(posedge clk) begin
    if (!rst_n || !(bus_req_o && !bus_dir_o && !bus_rready_i)) fv_rd_wait <= '0;
    else if (fv_rd_wait < 4'd8) fv_rd_wait <= fv_rd_wait + 4'd1;

    if (!rst_n || fv_rd_rise17) fv_rd_max_wait <= 1'b0;
    else if (fv_bus_accept && !bus_dir_o && fv_rd_wait == 4'd8) fv_rd_max_wait <= 1'b1;
  end

  // ---------------------------------------------------------------------------
  // spi_miso_o
  // ---------------------------------------------------------------------------

  // At the rises of bits 25-40 of a read frame, MISO = R[7]..R[0], R[15]..R[8]
  // (MSB first, low byte first). Checked on frame bit 40-fv_idx, so all 16 bits
  // over all fv_idx (Impl spec §3, T1, T2, HL-05, D-HL-5, V2, V4)
  ast_1110_miso_read_data: assert property(
    @(posedge clk) disable iff (!rst_n)
      (fv_frame_rise && fv_frame_read && fv_bit_cnt == 6'd39 - fv_idx) -> (spi_miso_o == fv_rbit)
  );

  // ---------------------------------------------------------------------------
  // bus_req_o
  // ---------------------------------------------------------------------------

  // A read request rises at E3 after the 17th rise with MOSI = 1 (Impl spec §3, §6 T2, T4, D-HL-5, V5)
  ast_1207_rd_req_at_e3: assert property(
    @(posedge clk) disable iff (!rst_n)
      ($past(fv_rd_rise17, 3) && fv_clks_out_of_rst == 2'd3) -> ($rose(bus_req_o) && !bus_dir_o)
  );

  // A read request only comes 3 clocks after a 17th rise with MOSI = 1:
  // none before bit 17, none when bit 17 = 0, none within 3 clocks of reset release
  // (Impl spec §3, §6 T2, T4, D-HL-5, V5)
  ast_1207_rd_req_only_after_bit17: assert property(
    @(posedge clk) disable iff (!rst_n)
      ($rose(bus_req_o) && !bus_dir_o) -> ($past(fv_rd_rise17, 3) && fv_clks_out_of_rst == 2'd3)
  );

  // A write request rises at E3 after the 40th rise of a write frame (Impl spec §3, §6 T3, V1)
  ast_1208_wr_req_at_e3: assert property(
    @(posedge clk) disable iff (!rst_n)
      ($past(fv_wr_rise40, 3) && fv_clks_out_of_rst == 2'd3) -> ($rose(bus_req_o) && bus_dir_o)
  );

  // A write request only comes 3 clocks after a 40th rise, so a frame with
  // fewer than 40 rises makes no write; none within 3 clocks of reset release
  // (Impl spec §3, HL-06, V5)
  ast_1209_no_wr_for_short_frame: assert property(
    @(posedge clk) disable iff (!rst_n)
      ($rose(bus_req_o) && bus_dir_o) -> ($past(fv_wr_rise40, 3) && fv_clks_out_of_rst == 2'd3)
  );

  // Every accepted access was issued by a frame and not yet accepted (A-CHG-2, HL-04, HL-05, BUS-05, V1, V2, V5)
  ast_1210_accept_only_when_owed: assert property(
    @(posedge clk) disable iff (!rst_n)
      fv_bus_accept -> fv_acc_owed
  );

  // The previous access is accepted before the next frame issues one (A-CHG-2, HL-04, HL-05, BUS-05, V1, V2, V5)
  ast_1210_no_issue_while_owed: assert property(
    @(posedge clk) disable iff (!rst_n)
      (fv_rd_rise17 || fv_wr_rise40) -> !fv_acc_owed
  );

  // SCK rises after bit 40 cause no request (Impl spec §3, V7)
  ast_1211_no_req_after_bit40: assert property(
    @(posedge clk) disable iff (!rst_n)
      ($past(fv_rise_after40, 3) && fv_clks_out_of_rst == 2'd3) -> !$rose(bus_req_o)
  );

  // ---------------------------------------------------------------------------
  // bus_dir_o, bus_addr_o, bus_wdata_o
  // ---------------------------------------------------------------------------

  // Accepted access direction = NOT frame bit 17 of its frame (Impl spec §3, V7)
  ast_1214_dir_matches_frame: assert property(
    @(posedge clk) disable iff (!rst_n)
      fv_bus_accept -> (bus_dir_o == fv_exp_dir)
  );

  // Accepted access address = {bits 9-16, bits 1-8} of its frame (A-CHG-1, Impl spec §3, T1, V1, V2, V7)
  ast_1217_addr_matches_frame: assert property(
    @(posedge clk) disable iff (!rst_n)
      fv_bus_accept -> (bus_addr_o == fv_exp_addr)
  );

  // Accepted write data = {bits 33-40, bits 25-32} of its frame (Impl spec §3, T1, A-CHG-2, V1)
  ast_1220_wdata_matches_frame: assert property(
    @(posedge clk) disable iff (!rst_n)
      (fv_bus_accept && bus_dir_o) -> (bus_wdata_o == fv_exp_wdata)
  );

  // ---------------------------------------------------------------------------
  // Covers
  // ---------------------------------------------------------------------------

  // 1110 is checked on a read-data bit that is 1 (Impl spec §3, T2)
  cov_1110_rd_data_bit_checked: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_frame_rise && fv_frame_read && fv_bit_cnt == 6'd39 - fv_idx && fv_rbit
  );

  // 1110 is checked on the first read-data bit (bit 25, R[7] = 1) of a read that
  // was accepted only after the full 8-clock wait (Impl spec §3, T2, BUS-02, D-HL-4, V4)
  cov_1110_first_bit_after_max_wait: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_rd_max_wait && fv_frame_rise && fv_frame_read && fv_bit_cnt == 6'd24 && fv_idx == 4'd15 && fv_rbit
  );

endmodule
