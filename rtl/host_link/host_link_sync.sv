// -----------------------------------------------------------------------------
// host_link_sync
//
// Synchronisers and SCK edge detect for the host link (spec F1, §4, §7).
//   - SCK, CS_n and MOSI each pass two flops of equal depth, so their edge
//     order is kept to within one clock.
//   - A third SCK flop (sck_d) keeps the previous value for edge detection.
//   - rise_en / fall_en are one-clock pulses, only while CS_n is low.
//
// Flops: 7 (sck_s1, sck_s2, sck_d, csn_s1, csn_s2, mosi_s1, mosi_s2).
// sck_s1, csn_s1 and mosi_s1 must be marked as synchroniser flops in the
// flow (P3). No logic in front of them.
// -----------------------------------------------------------------------------

module host_link_sync (
  input  wire clk,
  input  wire rst_n,

  // Asynchronous pins
  input  wire sck_i,
  input  wire csn_i,
  input  wire mosi_i,

  // Synchronised, to control and datapath
  output wire sel,       // CS_n low (synchronised)
  output wire rise_en,   // one-clock pulse after an SCK rise
  output wire fall_en,   // one-clock pulse after an SCK fall
  output wire mosi_s     // synchronised MOSI (mosi_s2)
);

  logic sck_s1, sck_s2, sck_d;
  logic csn_s1, csn_s2;
  logic mosi_s1, mosi_s2;

  // All reset to 0 (D-HL-8). For 2 clocks after reset csn_s2 = 0 (looks
  // selected), but sck_s2 = sck_d = 0 gives no edges, so nothing happens.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sck_s1  <= 1'b0;
      sck_s2  <= 1'b0;
      sck_d   <= 1'b0;
      csn_s1  <= 1'b0;
      csn_s2  <= 1'b0;
      mosi_s1 <= 1'b0;
      mosi_s2 <= 1'b0;
    end else begin
      sck_s1  <= sck_i;
      sck_s2  <= sck_s1;
      sck_d   <= sck_s2;
      csn_s1  <= csn_i;
      csn_s2  <= csn_s1;
      mosi_s1 <= mosi_i;
      mosi_s2 <= mosi_s1;
    end
  end

  assign sel     = ~csn_s2;
  assign rise_en =  sck_s2 & ~sck_d & sel;
  assign fall_en = ~sck_s2 &  sck_d & sel;
  assign mosi_s  =  mosi_s2;

endmodule
