// fv_host_link_host_if: host (SPI) interface properties of host_link.
// Only clk, rst_n and the SPI pins are used, so this file can also be used
// on the host side of the link. Testplan: ../testplan/host_link_fv_testplan.md
// Note: yosys-slang takes boolean properties only, so "a |-> b" is written
// "a -> b" and "a |=> b" is written "$past(a) -> b".

module fv_host_link_host_if (
  input logic clk,
  input logic rst_n,
  input logic spi_sck_i,
  input logic spi_csn_i,
  input logic spi_mosi_i,
  input logic spi_miso_o
);

  // ---------------------------------------------------------------------------
  // Helper logic
  // ---------------------------------------------------------------------------

  // SCK of the previous clock, for rise and fall detection
  logic fv_sck_q = 1'b0;
  always_ff @(posedge clk) fv_sck_q <= spi_sck_i;

  logic fv_sck_rise, fv_sck_fall;
  assign fv_sck_rise = spi_sck_i && !fv_sck_q;
  assign fv_sck_fall = !spi_sck_i && fv_sck_q;

  // SCK edge timer: clocks the current SCK level has lasted (saturates at 5)
  logic [2:0] fv_sck_level_len = '0;
  always_ff @(posedge clk)
    if (spi_sck_i != fv_sck_q) fv_sck_level_len <= 3'd1;
    else if (fv_sck_level_len < 3'd5) fv_sck_level_len <= fv_sck_level_len + 3'd1;

  // SCK edge timer: clocks since the last SCK rise (saturates at 10, set to 10 by reset)
  logic [3:0] fv_clks_since_rise = 4'd10;
  always_ff @(posedge clk)
    if (!rst_n) fv_clks_since_rise <= 4'd10;
    else if (fv_sck_rise) fv_clks_since_rise <= 4'd1;
    else if (fv_clks_since_rise < 4'd10) fv_clks_since_rise <= fv_clks_since_rise + 4'd1;

  // MOSI stability counter: clocks MOSI has kept its value (saturates at 5)
  logic       fv_mosi_q = 1'b0;
  logic [2:0] fv_mosi_level_len = '0;
  always_ff @(posedge clk) begin
    fv_mosi_q <= spi_mosi_i;
    if (spi_mosi_i != fv_mosi_q) fv_mosi_level_len <= 3'd1;
    else if (fv_mosi_level_len < 3'd5) fv_mosi_level_len <= fv_mosi_level_len + 3'd1;
  end

  // SPI host frame model: number of SCK rises seen in this frame (0..40),
  // cleared while CS_n is high; fv_rd_frame = MOSI at the 17th rise (R/W bit)
  logic [5:0] fv_bit_cnt;
  logic       fv_rd_frame;
  always_ff @(posedge clk)
    if (!rst_n || spi_csn_i) fv_bit_cnt <= '0;
    else if (fv_sck_rise && fv_bit_cnt < 6'd40) begin
      fv_bit_cnt <= fv_bit_cnt + 6'd1;
      if (fv_bit_cnt == 6'd16) fv_rd_frame <= spi_mosi_i;
    end

  // Read-data window: SCK rises 25..40 of a read frame
  logic fv_rd_window;
  assign fv_rd_window = fv_rd_frame && fv_bit_cnt >= 6'd24 && fv_bit_cnt <= 6'd39;

  // Set by reset, cleared once CS_n is seen high (host restarts its frame)
  logic fv_wait_cs_high;
  always_ff @(posedge clk)
    if (!rst_n) fv_wait_cs_high <= 1'b1;
    else if (spi_csn_i) fv_wait_cs_high <= 1'b0;

  // Set once reset has been released (initialized, so a cover cannot be hit by the
  // arbitrary start values of the helper flops in the first clock)
  logic fv_rst_released = 1'b0;
  always_ff @(posedge clk) if (rst_n) fv_rst_released <= 1'b1;

  // Set once a frame has had all 40 SCK rises (for the next-frame cover)
  logic fv_full_frame_seen;
  always_ff @(posedge clk)
    if (!rst_n) fv_full_frame_seen <= 1'b0;
    else if (fv_bit_cnt == 6'd40) fv_full_frame_seen <= 1'b1;

  // ---------------------------------------------------------------------------
  // spi_sck_i
  // ---------------------------------------------------------------------------

  // Each SCK high and low level lasts at least 5 clocks, SCK <= clk/10 (Impl spec §3 port table, H-1, HL-02)
  asm_1101_sck_level_min_5_clks: assume property(
    @(posedge clk) disable iff (!rst_n)
      (fv_sck_level_len < 3'd5) -> (spi_sck_i == fv_sck_q)
  );

  // SCK is 0 in reset and while CS_n is high: mode 0 idle level (H-1, HL-01, Impl spec §7 reset)
  asm_1102_sck_idle_low: assume property(
    @(posedge clk)
      (!rst_n || spi_csn_i) -> !spi_sck_i
  );

  // At least 10 clocks from the last SCK rise of a frame to the first rise of the next.
  // Written for every pair of rises; inside a frame 1101 already gives it (H-2, V6)
  asm_1103_frame_gap_min_10_clks: assume property(
    @(posedge clk) disable iff (!rst_n)
      (fv_clks_since_rise < 4'd10) -> !fv_sck_rise
  );

  // ---------------------------------------------------------------------------
  // spi_csn_i
  // ---------------------------------------------------------------------------

  // CS_n changes only while SCK is 0 (H-1, HL-01, Impl spec §3)
  asm_1104_csn_stable_sck_high: assume property(
    @(posedge clk) disable iff (!rst_n)
      spi_sck_i -> $stable(spi_csn_i)
  );

  // No read abort: CS_n stays low from the 17th rise (R/W = 1) to the 40th (H-3)
  asm_1105_no_read_abort: assume property(
    @(posedge clk) disable iff (!rst_n)
      (fv_rd_frame && fv_bit_cnt >= 6'd17 && fv_bit_cnt <= 6'd39) -> !spi_csn_i
  );

  // After reset, CS_n is high for at least one clock before the next SCK rise (HL-07, V7)
  asm_1106_csn_high_after_reset: assume property(
    @(posedge clk) disable iff (!rst_n)
      fv_wait_cs_high -> !spi_sck_i
  );

  // ---------------------------------------------------------------------------
  // spi_mosi_i
  // ---------------------------------------------------------------------------

  // MOSI is stable for 5 clocks before an SCK rise in a frame (Impl spec §7 CDC, H-1)
  asm_1107_mosi_stable_before_rise: assume property(
    @(posedge clk) disable iff (!rst_n)
      (!spi_csn_i && fv_mosi_level_len < 3'd5) -> !fv_sck_rise
  );

  // MOSI does not change while SCK is high in a frame (Impl spec §7 CDC, H-1)
  asm_1107_mosi_stable_sck_high: assume property(
    @(posedge clk) disable iff (!rst_n)
      (!spi_csn_i && spi_sck_i) -> $stable(spi_mosi_i)
  );

  // ---------------------------------------------------------------------------
  // spi_miso_o
  // ---------------------------------------------------------------------------

  // MISO is 0 in reset and in the first clock after reset release (D-HL-8, HL-07, HL-08, V9)
  ast_1108_miso_low_in_reset: assert property(
    @(posedge clk)
      (!rst_n || !$past(rst_n)) -> !spi_miso_o
  );

  // MISO is 0 when the host samples it outside the read-data window: bits 1-24,
  // bits 25-40 of a write frame, rises after bit 40 (Impl spec §3, HL-08, V8)
  ast_1109_miso_low_outside_rd_window: assert property(
    @(posedge clk) disable iff (!rst_n)
      (fv_sck_rise && !spi_csn_i && !fv_rd_window) -> !spi_miso_o
  );

  // MISO is 0 when idle: CS_n high for 4 clocks, so the E3 latency has passed (Impl spec §3, HL-08, V8)
  ast_1109_miso_low_when_idle: assert property(
    @(posedge clk) disable iff (!rst_n)
      (spi_csn_i && $past(spi_csn_i, 1) && $past(spi_csn_i, 2) && $past(spi_csn_i, 3)) -> !spi_miso_o
  );

  // During a frame, MISO changes only at E3 after an SCK fall, so it holds until
  // E3 after the next fall (Impl spec §3 port table, T5)
  ast_1111_miso_change_at_e3_after_fall: assert property(
    @(posedge clk) disable iff (!rst_n)
      (!spi_csn_i && $changed(spi_miso_o)) -> $past(fv_sck_fall, 3)
  );

  // ---------------------------------------------------------------------------
  // Covers
  // ---------------------------------------------------------------------------

  // A read frame reaches bit 40 with MISO = 1 (Impl spec §3, T2)
  cov_1110_rd_frame_bit40_miso_high: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_sck_rise && !spi_csn_i && fv_rd_frame && fv_bit_cnt == 6'd39 && spi_miso_o
  );

  // A frame is aborted: CS_n rises after 1 to 39 SCK rises (Impl spec §3, HL-06, V5)
  cov_1209_frame_abort: cover property(
    @(posedge clk) disable iff (!rst_n)
      $rose(spi_csn_i) && fv_bit_cnt >= 6'd1 && fv_bit_cnt <= 6'd39
  );

  // A write frame is aborted in its data bits: CS_n rises after 25 to 39 SCK rises,
  // with part of the write data shifted in (Impl spec §3, HL-06, V5)
  cov_1209_abort_in_wr_data: cover property(
    @(posedge clk) disable iff (!rst_n)
      $rose(spi_csn_i) && !fv_rd_frame && fv_bit_cnt >= 6'd25 && fv_bit_cnt <= 6'd39
  );

  // 1109 is checked at a data-bit rise of a write frame (bits 25-40) (Impl spec §3, HL-08, V8)
  cov_1109_wr_frame_data_rise: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_sck_rise && !spi_csn_i && !fv_rd_frame && fv_bit_cnt >= 6'd24 && fv_bit_cnt <= 6'd39
  );

  // Another frame starts after a full 40-bit frame: its first SCK rise (H-2, V6)
  cov_1103_next_frame_starts: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_full_frame_seen && fv_sck_rise && !spi_csn_i && fv_bit_cnt == 6'd0
  );

  // SCK rises after bit 40 in the same frame (ignored by the target) (Impl spec §3, V7)
  cov_1211_rise_after_bit40: cover property(
    @(posedge clk) disable iff (!rst_n)
      fv_sck_rise && !spi_csn_i && fv_bit_cnt == 6'd40
  );

  // Reset is applied in the middle of a frame (G-02, V7)
  cov_1003_reset_mid_frame: cover property(
    @(posedge clk)
      !rst_n && fv_rst_released && fv_bit_cnt >= 6'd1 && fv_bit_cnt <= 6'd39
  );

endmodule
