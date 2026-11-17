// -----------------------------------------------------------------------------
// sc_fifo_a
//
// FIFO A, FA_DEPTH x 17 bits (spec §4.10, O-02, D-SC-5): written over the bus
// (0x04 data, 0x05 tagged), read by SA.LOAD / stream reload, SA.SKIP and
// CNT.LDF. At most one pop per clock, priority SA > SA.SKIP > CNT.LDF; every
// consumer of the clock reads the head word. Each entry is clocked by its own
// clock gate (D-CG-1). FLUSH_A and SOFT_RESET clear the count only.
//
// FA_DEPTH must be a power of two (the spec uses 4); the count is 3 bits.
// Flops (FA_DEPTH = 4): mem 68, rp 2, cnt 3 = 73.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_fifo_a #(
  parameter FA_DEPTH = 4
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        clr,           // CTRL.FLUSH_A | CTRL.SOFT_RESET
  input  wire        wr,
  input  wire [6:0]  addr_i,
  input  wire [15:0] wdata_i,
  input  wire        sa_pop,
  input  wire        u_skip,
  input  wire        u_load,
  input  wire        u_ldf,
  input  wire        u_ldp,
  output reg  [2:0]  fa_cnt,
  output wire [16:0] fa_head,
  output wire        fa_ne,
  output wire        fa_ovr_set
);

  localparam PW = (FA_DEPTH > 2) ? $clog2(FA_DEPTH) : 1;

  reg  [PW-1:0]          fa_rp;
  wire [17*FA_DEPTH-1:0] mem;

  assign fa_ne = (fa_cnt != 3'd0);

  wire skip_pop = u_skip & ~u_load & fa_ne & ~sa_pop;
  wire ldf_pop  = u_ldf & ~u_ldp & fa_ne & ~sa_pop & ~skip_pop;
  wire fa_pop   = sa_pop | skip_pop | ldf_pop;

  wire push   = wr & ((addr_i == 7'h04) | (addr_i == 7'h05));
  assign fa_ovr_set = push & (fa_cnt == FA_DEPTH[2:0]);
  wire push_ok = push & ~fa_ovr_set;

  wire [PW-1:0] wslot = fa_rp + fa_cnt[PW-1:0];

  genvar i;
  generate
    for (i = 0; i < FA_DEPTH; i = i + 1) begin : g_e
      wire gclk;
      reg [16:0] e;
      icg u_icg (.clk(clk), .en(push_ok & (wslot == i)), .gclk(gclk));
      always @(posedge gclk or negedge rst_n) begin
        if (!rst_n)
          e <= 17'd0;
        else
          e <= {addr_i[0], wdata_i};
      end
      assign mem[17*i +: 17] = e;
    end
  endgenerate

  assign fa_head = fa_ne ? mem[17*fa_rp +: 17] : 17'd0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fa_rp  <= {PW{1'b0}};
      fa_cnt <= 3'd0;
    end else begin
      fa_rp  <= fa_rp + {{(PW-1){1'b0}}, fa_pop};
      fa_cnt <= clr ? 3'd0 : fa_cnt - {2'b00, fa_pop} + {2'b00, push_ok};
    end
  end

endmodule
