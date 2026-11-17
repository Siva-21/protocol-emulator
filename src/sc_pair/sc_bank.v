// -----------------------------------------------------------------------------
// sc_bank
//
// Program bank (spec §4.2, architecture §4.10): 16 rows x 32 latches, written
// per half-row (row_en[2r+h], h = 0 bits 15:0, h = 1 bits 31:16) through one
// clock gate each, read by two 8:1 halves lo (rows 0-7) and hi (rows 8-15).
//
// Master (IS_MASTER = 1): own = state[3] ? hi(state) : lo(state);
//   instr = state[4] ? (state[3] ? p_hi_i : p_lo_i) : own.
// Partner (IS_MASTER = 0): the halves may follow the master's state
//   (24/8: lo; 32/0: lo and hi) and are exported as lo_o / hi_o;
//   instr = (split 24) ? hi_o : (state[3] ? hi_o : lo_o).
//
// SEQ_CFG.SPLIT (architecture §4.11 [6:5]): 0 = 16/16, 1 = 24/8, 2 = 32/0;
// the reserved code 3 reads as 16/16 (as sc11.py cfg_from_words).
// -----------------------------------------------------------------------------

`default_nettype none

module sc_bank #(
  parameter IS_MASTER = 0
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [31:0] row_en,
  input  wire [15:0] d,
  /* verilator lint_off UNUSEDSIGNAL */
  input  wire [4:0]  state,         // [4] master only
  input  wire [1:0]  m_split_i,     // partner only
  input  wire [2:0]  m_state_i,     // partner only
  input  wire [31:0] p_lo_i,        // master only
  input  wire [31:0] p_hi_i,        // master only
  /* verilator lint_on UNUSEDSIGNAL */
  output wire [31:0] lo_o,
  output wire [31:0] hi_o,
  output wire [31:0] instr
);

  wire [511:0] bank;                // row r at [32r +: 32]

  genvar i;
  generate
    for (i = 0; i < 32; i = i + 1) begin : g_half
      wire gclk;
      icg u_icg (.clk(clk), .en(row_en[i]), .gclk(gclk));
      lword #(.W(16)) u_l (.rst_n(rst_n), .g(gclk), .d(d), .q(bank[16*i +: 16]));
    end
  endgenerate

  wire [255:0] lo_rows = bank[255:0];
  wire [255:0] hi_rows = bank[511:256];

  generate
    if (IS_MASTER != 0) begin : g_m
      wire [31:0] own = state[3] ? hi_rows[32*state[2:0] +: 32] : lo_rows[32*state[2:0] +: 32];
      assign instr = state[4] ? (state[3] ? p_hi_i : p_lo_i) : own;
      assign lo_o  = 32'd0;
      assign hi_o  = 32'd0;
    end else begin : g_p
      wire       s24    = (m_split_i == 2'd1);
      wire       s32    = (m_split_i == 2'd2);
      wire       s16    = ~s24 & ~s32;
      wire [2:0] lo_sel = s16 ? state[2:0] : m_state_i;
      wire [2:0] hi_sel = s32 ? m_state_i  : state[2:0];
      assign lo_o  = lo_rows[32*lo_sel +: 32];
      assign hi_o  = hi_rows[32*hi_sel +: 32];
      assign instr = (s24 | state[3]) ? hi_o : lo_o;
    end
  endgenerate

endmodule
