// -----------------------------------------------------------------------------
// sysbus
//
// System bus (spec pe_sysbus, docs/Implementation_spec/
// Sysbus_Implementation_Specification.pdf v1.0; BUS-01 to BUS-06, A-CHG-8,
// D-MC-8; D-BUS-3 correction and D-BUS-5 to D-BUS-9 confirmed by the owner on
// 15 Nov 2026): two masters (0 host link, 1 main core) to the seven bus targets and
// the unmapped space, one clock per access, no wait states except the CRC
// unit's. Two paths:
//
//   host only   0x0000-0x01FF, 0x1C10-0x1C1F  main_ss target port (t_*), waits
//                                              on t_wready / t_rready (CRC busy)
//   chip bus    0x1000-0x11FF sub-core n = addr[8:7]   (sc_req_o[n])
//               0x1800-0x181F pin layer                (pl_req_o)
//               0x1C00-0x1C0F sys_ctrl                 (sys_req_o)
//               everything else: unmapped, accepted, reads 0, writes ignored
//
// On the chip bus the host goes first; the core is held while the host is
// on it (BUS-03, D-BUS-2). m_wready / m_rready depend only on the host's
// flops, never on m_req_i. Chip-bus targets get the full c_addr and broadcast
// dir / wdata (D-BUS-9).
//
// Read data (D-BUS-3, D-BUS-4, D-BUS-8): ts_q = {class, n} of the chip-bus
// address and hm_q = "host address local to main_ss" load every clock; in the
// clock after a read they select the read data (class 0 none, 1 sub-core,
// 2 pin layer, 3 sys_ctrl).
//
// Flops: ts_q 4, hm_q 1 = 5. No latches, no clock gating.
// -----------------------------------------------------------------------------

`default_nettype none

module sysbus (
  input  wire        clk,
  input  wire        rst_n,
  // master 0: host link
  input  wire        h_req_i,
  input  wire        h_dir_i,        // 1 = write
  input  wire [15:0] h_addr_i,
  input  wire [15:0] h_wdata_i,
  output wire        h_wready_o,
  output wire        h_rready_o,
  output wire [15:0] h_rdata_o,      // valid in the clock after an accepted read
  // master 1: main_ss master port
  input  wire        m_req_i,
  input  wire        m_dir_i,
  input  wire [15:0] m_addr_i,
  input  wire [15:0] m_wdata_i,
  output wire        m_wready_o,
  output wire        m_rready_o,
  output wire [15:0] m_rdata_o,
  // target: main_ss (host only)
  output wire        t_req_o,
  output wire        t_dir_o,
  output wire [15:0] t_addr_o,
  output wire [15:0] t_wdata_o,
  input  wire        t_wready_i,
  input  wire        t_rready_i,
  input  wire [15:0] t_rdata_i,
  // chip-bus targets: one-hot req, broadcast dir / addr / wdata, all never wait
  output wire        sys_req_o,      // sys_ctrl, 0x1C00-0x1C0F
  output wire [3:0]  sc_req_o,       // sub-core n, 0x1000 + 0x80*n
  output wire        pl_req_o,       // pin layer, 0x1800-0x181F
  output wire        c_dir_o,
  output wire [15:0] c_addr_o,       // sys_ctrl uses [3:0], sub-cores [6:0], pin layer [4:0]
  output wire [15:0] c_wdata_o,
  input  wire [15:0] sys_rdata_i,
  input  wire [63:0] sc_rdata_i,     // {SC3, SC2, SC1, SC0}
  input  wire [15:0] pl_rdata_i
);

  // ---- host decode and ready (§4.1)
  wire h_mcu  = (h_addr_i[15:9] == 7'd0) | (h_addr_i[15:4] == 12'h1C1);
  wire h_chip = h_req_i & ~h_mcu;

  assign t_req_o   = h_req_i & h_mcu;
  assign t_dir_o   = h_dir_i;
  assign t_addr_o  = h_addr_i;
  assign t_wdata_o = h_wdata_i;

  assign h_wready_o = ~h_mcu | t_wready_i;
  assign h_rready_o = ~h_mcu | t_rready_i;
  assign m_wready_o = ~h_chip;               // host first (BUS-03, D-BUS-2)
  assign m_rready_o = ~h_chip;

  // ---- chip bus (§4.2)
  wire        c_req   = h_chip | m_req_i;
  wire [15:0] c_addr  = h_chip ? h_addr_i  : m_addr_i;
  assign c_dir_o   = h_chip ? h_dir_i   : m_dir_i;
  assign c_wdata_o = h_chip ? h_wdata_i : m_wdata_i;
  assign c_addr_o  = c_addr;

  wire       top    = (c_addr[15:12] == 4'h1);
  wire       is_sc  = top & (c_addr[11:9] == 3'b000);          // 0x1000-0x11FF
  wire       is_pl  = top & (c_addr[11:5] == 7'b1000000);      // 0x1800-0x181F
  wire       is_sys = top & (c_addr[11:4] == 8'b11000000);     // 0x1C00-0x1C0F
  wire [1:0] n      = c_addr[8:7];

  genvar k;
  generate
    for (k = 0; k < 4; k = k + 1) begin : g_sc
      assign sc_req_o[k] = c_req & is_sc & (n == k);
    end
  endgenerate
  assign pl_req_o  = c_req & is_pl;
  assign sys_req_o = c_req & is_sys;

  // ---- read data (§4.3)
  wire [1:0] cls = {is_pl | is_sys, is_sc | is_sys};   // 0 none, 1 sc, 2 pl, 3 sys

  reg [3:0] ts_q;
  reg       hm_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ts_q <= 4'd0;
      hm_q <= 1'b0;
    end else begin
      ts_q <= {cls, n};
      hm_q <= h_mcu;
    end
  end

  wire [15:0] x = sc_rdata_i[16*ts_q[1:0] +: 16];
  reg  [15:0] c_rdata;
  always @(*) begin
    case (ts_q[3:2])
      2'd1:    c_rdata = x;
      2'd2:    c_rdata = pl_rdata_i;
      2'd3:    c_rdata = sys_rdata_i;
      default: c_rdata = 16'd0;
    endcase
  end

  assign m_rdata_o = c_rdata;
  assign h_rdata_o = hm_q ? t_rdata_i : c_rdata;

endmodule
