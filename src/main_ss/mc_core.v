// -----------------------------------------------------------------------------
// mc_core
//
// Main core (main_ss spec §5, figures F2, F3): control, decode,
// register file, ALU and bus master port. Reference model: mc11.py.
//
//   - A_DOUT of the SRAM (dout_i) is the instruction register (D-MC-4); irv
//     says it holds the instruction at pc. No IR flops.
//   - Control states are decoded from three flops, not stored (§5.2):
//       WB      ldp_v                    pending load writes back
//       HALTED  ~ldp_v & ~mc_run         prefetches pc if irv = 0 (D-MC-11)
//       FETCH   ~ldp_v &  mc_run & ~irv
//       EXEC    ~ldp_v &  mc_run &  irv  executes dout_i, or stalls
//   - A pending load completes in WB even when mc_run has fallen (D-MC-7).
//   - Every load writes back in the clock after issue (D-MC-12). A taken
//     branch / jump still requests the sequential fetch; the word is
//     discarded (D-MC-13).
//   - 9-bit pc, wraps modulo 512; JAL links {7'b0, pc + 1} (D-MC-3).
//   - SHI type 3 = SRA (D-MC-1); SYS fn 4..63 = NOP (D-MC-2).
//   - Register file r1-r7 in flops (D-MC-6), each row on its own gated clock
//     (icg, D-MC-14). One write port, two read ports; r0 reads 0.
//
// Flops: 130 (pc 9, irv 1, ldp_v 1, ldp_rd 3, ldp_src 2, ldp_byte 1,
// ldp_bsel 1, r1-r7 112).
// -----------------------------------------------------------------------------

`default_nettype none

module mc_core (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        mc_run_i,
  input  wire [15:0] wait_i,
  output wire        mc_halt_o,
  output wire        mc_irq_o,
  // SRAM side
  input  wire [15:0] dout_i,       // A_DOUT
  input  wire        port_free_i,  // !h_sram
  input  wire        h_rd_i,
  input  wire        h_wr_i,
  input  wire [8:0]  h_addr_i,
  output wire        dreq_o,       // data access (issued only if port_free_i)
  output wire        dwe_o,
  output wire [8:0]  daddr_o,
  output wire [15:0] ddin_o,
  output wire [15:0] dbm_o,
  output wire        freq_o,       // fetch request
  output wire [8:0]  faddr_o,
  // CRC block side
  input  wire        crc_busy_i,
  input  wire        h_crc_i,
  input  wire [15:0] crc_rdata_i,
  output wire        creq_o,
  output wire        cwe_o,
  output wire [3:0]  coff_o,
  output wire [15:0] cwdata_o,
  // Bus master
  output wire        m_req_o,
  output wire        m_dir_o,
  output wire [15:0] m_addr_o,
  output wire [15:0] m_wdata_o,
  input  wire        m_wready_i,
  input  wire        m_rready_i,
  input  wire [15:0] m_rdata_i
);

  // ---------------------------------------------------------------------------
  // State (§5.2)
  // ---------------------------------------------------------------------------
  reg [8:0] pc;
  reg       irv;
  reg       ldp_v;
  reg [2:0] ldp_rd;
  reg [1:0] ldp_src;    // 0 SRAM, 1 CRC block, 2 chip bus
  reg       ldp_byte;
  reg       ldp_bsel;

  wire st_wb    =  ldp_v;
  wire st_halt  = ~ldp_v & ~mc_run_i;
  wire st_fetch = ~ldp_v &  mc_run_i & ~irv;
  wire st_exec  = ~ldp_v &  mc_run_i &  irv;

  // ---------------------------------------------------------------------------
  // Decode (§5.3, Appendix A)
  // ---------------------------------------------------------------------------
  wire [15:0] I   = dout_i;
  wire [3:0]  op  = I[15:12];
  wire [2:0]  rd  = I[11:9];
  wire [2:0]  rs  = I[8:6];
  wire [2:0]  rt  = I[5:3];
  wire [2:0]  fn3 = I[2:0];
  wire [5:0]  fn6 = I[5:0];

  wire c_alu  = op == 4'h0;
  wire c_addi = op == 4'h1;
  wire c_shi  = op == 4'h2;
  wire c_andi = op == 4'h3;
  wire c_ld   = op == 4'h4;
  wire c_st   = op == 4'h5;
  wire c_beq  = op == 4'h6;
  wire c_bne  = op == 4'h7;
  wire c_li   = op == 4'h8;
  wire c_lih  = op == 4'h9;
  wire c_jmp  = op == 4'hA;
  wire c_jal  = op == 4'hB;
  wire c_sys  = op == 4'hC;
  wire c_bltu = op == 4'hD;
  wire c_ldb  = op == 4'hE;
  wire c_stb  = op == 4'hF;
  wire c_jr   = c_sys & (fn6 == 6'd0);
  wire c_wait = c_sys & (fn6 == 6'd1);
  wire c_halt = c_sys & (fn6 == 6'd2);
  wire c_irq  = c_sys & (fn6 == 6'd3);   // fn6 4..63: NOP (D-MC-2)

  // Register file read ports: R(0) = 0
  wire [16*8-1:0] rf;
  wire [15:0] A = rf[16*rs +: 16];
  wire [2:0]  rb = c_alu ? rt : rd;                 // port B: rt for op 0, rd otherwise
  wire [15:0] B = rf[16*rb +: 16];

  wire [15:0] ea = A + {10'd0, I[5:0]};             // LD/ST/LDB/STB, 16-bit, wraps

  wire is_load  = c_ld | c_ldb;
  wire is_store = c_st | c_stb;
  wire is_byte  = c_ldb | c_stb;
  wire is_mem   = is_load | is_store;
  wire to_sram  = is_mem & (is_byte | (ea[15:9] == 7'd0));
  wire to_crc   = is_mem & ~is_byte & (ea[15:4] == 12'h1C1);
  wire to_bus   = is_mem & ~to_sram & ~to_crc;

  // ---------------------------------------------------------------------------
  // Execute, stall and go (§5.4)
  // ---------------------------------------------------------------------------
  wire        eq     = (B == A);                    // BEQ/BNE: R[rd] vs R[rs]
  wire        ltu    = (B < A);                     // BLTU: R[rd] < R[rs], unsigned
  wire        taken  = (c_beq & eq) | (c_bne & ~eq) | (c_bltu & ltu);
  wire [15:0] hit    = wait_i & A;                  // WAIT rd, rs
  wire        crc_wt = crc_busy_i & (is_store ? (ea[3:0] == 4'h3)
                                              : ((ea[3:0] == 4'h4) | (ea[3:0] == 4'h5)));

  wire stall = st_exec & ( (to_sram & ~port_free_i)
                         | (to_crc  & (h_crc_i | crc_wt))
                         | (to_bus  & ~(is_store ? m_wready_i : m_rready_i))
                         | (c_wait  & (hit == 16'd0)) );
  wire go    = st_exec & ~stall;
  wire redir = go & (taken | c_jmp | c_jal | c_jr);

  // Next pc (9 bits, wraps)
  wire [8:0] pc1    = pc + 9'd1;
  wire [8:0] br_tgt = pc1 + {{3{I[5]}}, I[5:0]};    // sext(off6)
  wire [8:0] jp_tgt = pc1 + I[8:0];                 // off12 mod 512
  wire [8:0] pc_n   = ~go             ? pc
                    : taken           ? br_tgt
                    : (c_jmp | c_jal) ? jp_tgt
                    : c_jr            ? A[8:0]
                    :                   pc1;

  // Fetch request and SRAM data request (D-MC-13)
  wire ld_reg  = go & is_load & (to_crc | to_bus);   // register-block load: no fetch
  assign dreq_o  = go & to_sram;
  assign dwe_o   = is_store;
  assign daddr_o = is_byte ? ea[9:1] : ea[8:0];
  assign ddin_o  = c_stb ? {B[7:0], B[7:0]} : B;
  assign dbm_o   = c_stb ? (ea[0] ? 16'hFF00 : 16'h00FF) : 16'hFFFF;
  assign freq_o  = (go & ~to_sram & ~ld_reg) | (st_wb & mc_run_i) | st_fetch | (st_halt & ~irv);
  assign faddr_o = st_exec ? pc1 : pc;
  wire   fetched = freq_o & port_free_i;            // dreq_o and freq_o are never both 1

  // Instruction valid, priority top to bottom
  wire irv_n = h_rd_i                       ? 1'b0                 // host read replaced dout
             : (h_wr_i & (h_addr_i == pc))  ? 1'b0                 // host overwrote the held word (D-MC-11)
             : freq_o                       ? (fetched & ~redir)
             : go                           ? 1'b0                 // SRAM load/store or register-block load
             :                                irv;                 // stall, halted with irv, WB while halted

  // Pending load (fields load every clock; used only when ldp_v = 1)
  wire       ldp_v_n   = go & is_load;
  wire [1:0] ldp_src_n = to_sram ? 2'd0 : to_crc ? 2'd1 : 2'd2;

  // Outputs
  assign mc_halt_o = go & c_halt;
  assign mc_irq_o  = go & c_irq;
  assign creq_o    = go & to_crc;           // h_crc_i and crc_wt are already in stall
  assign cwe_o     = is_store;
  assign coff_o    = ea[3:0];
  assign cwdata_o  = B;
  assign m_req_o   = st_exec & to_bus;      // also while not accepted
  assign m_dir_o   = is_store;
  assign m_addr_o  = ea;
  assign m_wdata_o = B;

  // ---------------------------------------------------------------------------
  // Results and register write (§5.5)
  // ---------------------------------------------------------------------------
  wire [3:0]  sh_amt  = c_shi ? I[3:0] : B[3:0];
  wire [1:0]  sh_type = c_shi ? I[5:4] : (fn3 == 3'd5) ? 2'd0 : (fn3 == 3'd6) ? 2'd1 : 2'd2;  // 3 = SRA (D-MC-1)
  wire [15:0] sh_out  = (sh_type == 2'd0) ? (A << sh_amt)
                      : (sh_type == 2'd1) ? (A >> sh_amt)
                      :                     ($signed(A) >>> sh_amt);
  wire [15:0] alu_out = (fn3 == 3'd0) ? A + B
                      : (fn3 == 3'd1) ? A - B
                      : (fn3 == 3'd2) ? A & B
                      : (fn3 == 3'd3) ? A | B
                      : (fn3 == 3'd4) ? A ^ B
                      :                 sh_out;
  wire [15:0] res = c_alu  ? alu_out
                  : c_addi ? A + {{10{I[5]}}, I[5:0]}
                  : c_shi  ? sh_out
                  : c_andi ? A & {10'd0, I[5:0]}
                  : c_li   ? {{7{I[8]}}, I[8:0]}
                  : c_lih  ? {I[7:0], B[7:0]}
                  :          hit;                   // WAIT
  wire wr_res = c_alu | c_addi | c_shi | c_andi | c_li | c_lih | c_wait;

  // Load writeback data (WB state)
  wire [15:0] ld_word = (ldp_src == 2'd0) ? dout_i
                      : (ldp_src == 2'd1) ? crc_rdata_i
                      :                     m_rdata_i;
  wire [15:0] ld_data = ldp_byte ? {8'd0, ldp_bsel ? ld_word[15:8] : ld_word[7:0]} : ld_word;

  // One write port
  wire        rf_we = (st_wb & (ldp_rd != 3'd0)) | (go & wr_res & (rd != 3'd0)) | (go & c_jal);
  wire [2:0]  rf_wa = st_wb ? ldp_rd : c_jal ? 3'd7 : rd;
  wire [15:0] rf_wd = st_wb ? ld_data : c_jal ? {7'd0, pc1} : res;

  // ---------------------------------------------------------------------------
  // Register file with clock gating (§5.6, D-MC-14)
  // ---------------------------------------------------------------------------
  assign rf[15:0] = 16'd0;                          // r0

  genvar k;
  generate
    for (k = 1; k < 8; k = k + 1) begin : g_row
      wire       gclk;
      reg [15:0] r;
      icg u_icg (.clk(clk), .en(rf_we & (rf_wa == k)), .gclk(gclk));
      always @(posedge gclk or negedge rst_n)
        if (!rst_n) r <= 16'd0;
        else        r <= rf_wd;
      assign rf[16*k +: 16] = r;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Control registers: all reset to 0
  // ---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc       <= 9'd0;
      irv      <= 1'b0;
      ldp_v    <= 1'b0;
      ldp_rd   <= 3'd0;
      ldp_src  <= 2'd0;
      ldp_byte <= 1'b0;
      ldp_bsel <= 1'b0;
    end else begin
      pc       <= pc_n;
      irv      <= irv_n;
      ldp_v    <= ldp_v_n;
      ldp_rd   <= rd;
      ldp_src  <= ldp_src_n;
      ldp_byte <= c_ldb;
      ldp_bsel <= ea[0];
    end
  end

endmodule
