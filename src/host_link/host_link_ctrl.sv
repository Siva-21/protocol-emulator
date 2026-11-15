// -----------------------------------------------------------------------------
// host_link_ctrl
//
// Control path of the host link (spec §4 control logic, §5 state machines).
// Two independent machines:
//
//   A. Frame FSM, state ph[1:0] + bit counter bc[3:0], steps on rise_en.
//        ADDR (00) bc 0..15 -> CMD (01) bc 8..15 -> DATA (10) bc 0..15
//        -> DONE (11, saturates, SCK ignored).
//      CS_n high (sel = 0) from any state: ph <- ADDR, bc <- 0.
//
//   B. Bus request FSM, state {req, rw, rpend}, runs every clock and ignores
//      CS_n, so an accepted access always completes.
//        IDLE --set_wr--> WAIT_W --wready--> IDLE
//        IDLE --set_rd--> WAIT_R --rready--> RDATA (rpend) --> IDLE
//
// Produces every enable for the datapath; holds no data.
// Flops: 9 (ph 2, bc 4, rw 1, req 1, rpend 1).
// -----------------------------------------------------------------------------

module host_link_ctrl (
  input  wire clk,
  input  wire rst_n,

  // From host_link_sync
  input  wire sel,
  input  wire rise_en,
  input  wire fall_en,
  input  wire mosi_s,

  // System bus handshake
  input  wire wready_i,
  input  wire rready_i,
  output wire req_o,
  output wire dir_o,       // 1 = write, 0 = read

  // Datapath enables
  output wire a_sh_o,      // shift MOSI into the address register
  output wire sr_shift_o,  // shift sr (write: in on rise; read: out on fall)
  output wire sr_load_o,   // load sr from rdata_i (rpend)
  output wire miso_en_o    // MISO may drive sr[15] (read-data bytes)
);

  // Frame phase encoding (spec §4)
  localparam [1:0] PH_ADDR = 2'b00;
  localparam [1:0] PH_CMD  = 2'b01;
  localparam [1:0] PH_DATA = 2'b10;
  localparam [1:0] PH_DONE = 2'b11;

  logic [1:0] ph;     // frame phase
  logic [3:0] bc;     // bit counter
  logic       rw;     // R/W bit of the current command
  logic       req;    // bus request
  logic       rpend;  // read data due this clock

  // ---------------------------------------------------------------------------
  // A. Frame FSM
  // ---------------------------------------------------------------------------
  wire ph_addr = (ph == PH_ADDR);
  wire ph_cmd  = (ph == PH_CMD);
  wire ph_data = (ph == PH_DATA);
  wire ph_done = (ph == PH_DONE);

  wire tc  = (bc == 4'd15);             // AND4: ends each phase
  wire b8  = (bc == 4'd8);              // AND4: frame bit 17 in CMD
  wire bnz = (bc != 4'd0);              // OR4

  // inc = bc + 1, as the spec's ripple equations
  wire i0 = ~bc[0];
  wire i1 =  bc[1] ^  bc[0];
  wire i2 =  bc[2] ^ (bc[1] & bc[0]);
  wire i3 =  bc[3] ^ (bc[2] & bc[1] & bc[0]);

  // ADDR -> CMD: bc + 1 = 0, so OR-ing 8 into bit 3 loads 8 (CMD lasts 8 bits)
  wire ld8 = ph_addr & tc;

  wire [3:0] bc_d   = sel ? (rise_en ? {i3 | ld8, i2, i1, i0} : bc) : 4'd0;

  wire       ph_inc = rise_en & tc & ~ph_done;
  wire [1:0] ph_d   = sel ? (ph_inc ? ph + 2'd1 : ph) : PH_ADDR;   // DONE saturates

  // ---------------------------------------------------------------------------
  // B. Bus request FSM
  // ---------------------------------------------------------------------------
  wire cap    = rise_en & ph_cmd & b8;        // frame bit 17, the R/W bit
  wire rw_d   = cap ? mosi_s : rw;
  wire set_rd = cap & mosi_s;                 // read issued on bit 17
  wire set_wr = rise_en & ph_data & tc & ~rw; // write issued after bit 40

  wire acc     = req & (rw ? rready_i : wready_i);
  wire req_d   = set_rd | set_wr | (req & ~acc);
  wire rpend_d = req & rw & rready_i;

  // ---------------------------------------------------------------------------
  // Registers: all reset to 0 (D-HL-8)
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ph    <= PH_ADDR;
      bc    <= 4'd0;
      rw    <= 1'b0;
      req   <= 1'b0;
      rpend <= 1'b0;
    end else begin
      ph    <= ph_d;
      bc    <= bc_d;
      rw    <= rw_d;
      req   <= req_d;
      rpend <= rpend_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Outputs
  // ---------------------------------------------------------------------------
  assign req_o      = req;
  assign dir_o      = ~rw;

  assign a_sh_o     = rise_en & ph_addr;
  // bnz blocks the shift on the first DATA fall, so R[7] stays on MISO for bit 25
  assign sr_shift_o = (rise_en & ph_data & ~rw) | (fall_en & ph_data & rw & bnz);
  assign sr_load_o  = rpend;
  assign miso_en_o  = rw & ph_data;

endmodule
