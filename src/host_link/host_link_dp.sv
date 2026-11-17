// -----------------------------------------------------------------------------
// host_link_dp
//
// Datapath of the host link (spec §4 datapath): the two 16-bit shift
// registers that do the serial <-> parallel conversion. All enables come
// from host_link_ctrl; this block makes no decisions.
//
//   a[15:0]  : collects the address during ADDR (frame bits 1-16), holds it
//              until the next frame. Fields arrive low byte first, MSB-first,
//              so a = {A[7:0], A[15:8]} and addr_o swaps the bytes back.
//   sr[15:0] : write - shifts MOSI in on SCK rises (frame bits 25-40);
//              read  - loads swap(rdata_i) on rpend, shifts out on SCK falls.
//              During a read sr also fills from MOSI, but those bits never
//              reach sr[15] within 15 shifts, so they never appear on MISO.
//
// No write-hold register (D-HL-6): addr_o/wdata_o are wiring from a/sr and
// are kept stable by host rule H-2.
// Flops: 32 (a 16, sr 16).
// -----------------------------------------------------------------------------

module host_link_dp (
  input  wire        clk,
  input  wire        rst_n,

  // Serial in
  input  wire        mosi_s,     // synchronised MOSI

  // Enables from host_link_ctrl
  input  wire        a_sh,
  input  wire        sr_shift,
  input  wire        sr_load,
  input  wire        miso_en,

  // Parallel side (system bus)
  input  wire [15:0] rdata_i,
  output wire [15:0] addr_o,
  output wire [15:0] wdata_o,

  // Serial out
  output wire        miso_o
);

  logic [15:0] a;   // address shift register
  logic [15:0] sr;  // write data in, read data out

  wire [15:0] a_d  = a_sh     ? {a[14:0], mosi_s}                 : a;
  wire [15:0] sr_d = sr_load  ? {rdata_i[7:0], rdata_i[15:8]}     :
                     sr_shift ? {sr[14:0], mosi_s}                :
                                sr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a  <= 16'd0;
      sr <= 16'd0;
    end else begin
      a  <= a_d;
      sr <= sr_d;
    end
  end

  assign addr_o  = {a[7:0],  a[15:8]};
  assign wdata_o = {sr[7:0], sr[15:8]};
  assign miso_o  = sr[15] & miso_en;   // 0 outside the read-data bytes (HL-08)

endmodule
