// -----------------------------------------------------------------------------
// crc_bs
//
// CRC and bit-stream unit, registers 0x1C10-0x1C19 (main_ss spec §8,
// figure F5, A-CHG-5, A-CHG-7, A-CHG-10, D-MC-15, D-MC-16, D-MC-17).
//
//   0x0 POLY_L   RW poly[15:0]                                  reset 0
//   0x1 POLY_H   RW poly[31:16]                                 reset 0
//   0x2 CFG      RW [4:0] wm1 (width - 1), [5] reflect          reset 0x0007
//   0x3 DATA     W  [7:0] data, [10:8] count (0 = 8); R 0       (waits while busy)
//   0x4 VAL_L    RW val[15:0]                                   (read waits while busy)
//   0x5 VAL_H    RW val[31:16]                                  (read waits while busy)
//   0x6 BS_CFG   RW [0] en, [1] rx, [2] k6, [3] nrzi, [4] pmsb  reset 0
//   0x7 BS_CTL   W  [0] = 1: clear;  BS_STAT R {serr, ovr, outv, 0, pkn}
//   0x8 BS_OUT   R  out; a read pops (outv = 0) unless a word loads this clock
//   0x9 BS_PART  R  pk (right-aligned, pkn bits valid)
//   0xA-0xF      R 0, writes ignored
//
// One bit per clock while busy = (cnt != 0) | ins. Per-clock step as in
// spec §8.4 (mc11.py BitStreamCRC.step); register writes are applied after the
// step and override it. Waiting (DATA write / VAL read while busy) is done by
// the target port and the core; this unit sees only accepted accesses.
//
// CFG wm1[2:0] and the NRZI level are stored inverted so that every flop
// resets to 0 (dfrbpq).
//
// Flops: 147 (poly 32, val 32, wm1 5, reflect 1, sr 8, cnt 4, bs_cfg 5,
// run 3, ins 1, lvl 1, pk 16, pkn 4, out 16, outv 1, ovr 1, serr 1, rdata_q 16).
// -----------------------------------------------------------------------------

`default_nettype none

module crc_bs (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        a_req,      // accepted access this clock (host or core)
  input  wire        a_we,       // 1 = write
  input  wire [3:0]  a_off,
  input  wire [15:0] a_wdata,
  output reg  [15:0] rdata_q,    // crc_rdata_q
  output wire        busy,
  output wire        outv
);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  reg [31:0] poly;
  reg [31:0] val;
  reg [4:0]  wm1_x;     // wm1 ^ 5'b00111 (reset 0 = width 8)
  reg        reflect;
  reg [7:0]  sr;
  reg [3:0]  cnt;
  reg        en, rx, k6, nrzi, pmsb;
  reg [2:0]  run;
  reg        ins;
  reg        lvl_n;     // ~lvl (reset 0 = level 1)
  reg [15:0] pk;
  reg [3:0]  pkn;
  reg [15:0] out;
  reg        outv_q, ovr, serr;

  wire [4:0] wm1 = wm1_x ^ 5'b00111;
  wire       lvl = ~lvl_n;

  assign busy = (cnt != 4'd0) | ins;
  assign outv = outv_q;

  wire [2:0]  k_run = k6 ? 3'd6 : 3'd5;
  wire [31:0] mask  = 32'hFFFF_FFFF >> (5'd31 - wm1);   // 2^W - 1, W = wm1 + 1
  wire        pop   = a_req & ~a_we & (a_off == 4'h8);
  wire        wr    = a_req & a_we;

  // ---------------------------------------------------------------------------
  // Per-clock step (§8.4) followed by register writes
  // ---------------------------------------------------------------------------
  reg [31:0] n_poly, n_val;
  reg [4:0]  n_wm1;
  reg        n_reflect;
  reg [7:0]  n_sr;
  reg [3:0]  n_cnt;
  reg        n_en, n_rx, n_k6, n_nrzi, n_pmsb;
  reg [2:0]  n_run;
  reg        n_ins, n_lvl;
  reg [15:0] n_pk;
  reg [3:0]  n_pkn;
  reg [15:0] n_out;
  reg        n_outv, n_ovr, n_serr;

  reg        b_in, b, fb, lvl_t, loaded;
  reg        do_crc, crc_b, do_emit, emit_e;
  reg [2:0]  run_u;
  reg [15:0] pk2;
  reg [3:0]  n_bits;

  always @* begin
    n_poly = poly;  n_val = val;  n_wm1 = wm1;  n_reflect = reflect;
    n_sr = sr;  n_cnt = cnt;
    n_en = en;  n_rx = rx;  n_k6 = k6;  n_nrzi = nrzi;  n_pmsb = pmsb;
    n_run = run;  n_ins = ins;  n_lvl = lvl;
    n_pk = pk;  n_pkn = pkn;  n_out = out;
    n_outv = outv_q;  n_ovr = ovr;  n_serr = serr;

    b_in = 1'b0;  b = 1'b0;  lvl_t = lvl;  run_u = 3'd0;
    do_crc = 1'b0;  crc_b = 1'b0;  do_emit = 1'b0;  emit_e = 1'b0;
    loaded = 1'b0;  n_bits = 4'd0;

    // ---- bit source --------------------------------------------------------
    if (ins) begin                                   // TX stuff bit
      n_ins = 1'b0;
      n_run = 3'd0;
      if (nrzi) begin
        n_lvl  = ~lvl;
        emit_e = ~lvl;
      end else begin
        emit_e = 1'b0;
      end
      do_emit = 1'b1;
    end else if (cnt != 4'd0) begin
      b_in  = reflect ? sr[0] : sr[7];
      n_sr  = reflect ? {1'b0, sr[7:1]} : {sr[6:0], 1'b0};
      n_cnt = cnt - 4'd1;
      if (!en) begin                                 // CRC only
        do_crc = 1'b1;
        crc_b  = b_in;
      end else if (!rx) begin                        // TX: stuff, NRZI encode
        do_crc = 1'b1;
        crc_b  = b_in;
        run_u  = b_in ? run + 3'd1 : 3'd0;
        n_run  = run_u;
        if (run_u == k_run) n_ins = 1'b1;
        if (nrzi) begin
          lvl_t  = b_in ? lvl : ~lvl;                // a 0 toggles the level
          n_lvl  = lvl_t;
          emit_e = lvl_t;
        end else begin
          emit_e = b_in;
        end
        do_emit = 1'b1;
      end else begin                                 // RX: NRZI decode, destuff
        b = nrzi ? (b_in == lvl) : b_in;
        if (nrzi) n_lvl = b_in;
        if (run == k_run) begin                      // stuff bit dropped
          n_serr = serr | b;
          n_run  = 3'd0;
        end else begin
          do_crc  = 1'b1;
          crc_b   = b;
          n_run   = b ? run + 3'd1 : 3'd0;
          do_emit = 1'b1;
          emit_e  = b;
        end
      end
    end

    // ---- CRC LFSR ----------------------------------------------------------
    fb = (reflect ? val[0] : val[wm1]) ^ crc_b;
    if (do_crc)
      n_val = reflect ? ((val >> 1) ^ (fb ? poly : 32'd0))
                      : (((val << 1) & mask) ^ (fb ? poly : 32'd0));

    // ---- packer ------------------------------------------------------------
    pk2 = pmsb ? {pk[14:0], emit_e}
               : ((pk & ~(16'd1 << pkn)) | ({15'd0, emit_e} << pkn));
    if (do_emit) begin
      if (pkn == 4'd15) begin
        n_out  = pk2;
        n_outv = 1'b1;
        n_pk   = 16'd0;
        n_pkn  = 4'd0;
        n_ovr  = ovr | (outv_q & ~pop);
        loaded = 1'b1;
      end else begin
        n_pk  = pk2;
        n_pkn = pkn + 4'd1;
      end
    end
    if (pop & ~loaded) n_outv = 1'b0;               // D-MC-16

    // ---- register writes override the step ---------------------------------
    if (wr) begin
      case (a_off)
        4'h0: n_poly[15:0]  = a_wdata;
        4'h1: n_poly[31:16] = a_wdata;
        4'h2: begin
          n_wm1     = a_wdata[4:0];
          n_reflect = a_wdata[5];
        end
        4'h3: begin                                  // DATA (accepted only when !busy)
          n_bits = (a_wdata[10:8] == 3'd0) ? 4'd8 : {1'b0, a_wdata[10:8]};
          n_cnt  = n_bits;
          n_sr   = reflect ? a_wdata[7:0] : (a_wdata[7:0] << (4'd8 - n_bits));
        end
        4'h4: n_val[15:0]  = a_wdata;
        4'h5: n_val[31:16] = a_wdata;
        4'h6: begin
          n_en   = a_wdata[0];
          n_rx   = a_wdata[1];
          n_k6   = a_wdata[2];
          n_nrzi = a_wdata[3];
          n_pmsb = a_wdata[4];
        end
        4'h7: if (a_wdata[0]) begin                  // BS_CTL clear
          n_pk   = 16'd0;
          n_pkn  = 4'd0;
          n_run  = 3'd0;
          n_ins  = 1'b0;
          n_lvl  = 1'b1;
          n_outv = 1'b0;
          n_ovr  = 1'b0;
          n_serr = 1'b0;
        end
        default: ;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Read mux: values at the start of the clock (§8.2)
  // ---------------------------------------------------------------------------
  reg [15:0] rmux;
  always @* begin
    case (a_off)
      4'h0:    rmux = poly[15:0];
      4'h1:    rmux = poly[31:16];
      4'h2:    rmux = {10'd0, reflect, wm1};
      4'h4:    rmux = val[15:0];
      4'h5:    rmux = val[31:16];
      4'h6:    rmux = {11'd0, pmsb, nrzi, k6, rx, en};
      4'h7:    rmux = {8'd0, serr, ovr, outv_q, 1'b0, pkn};
      4'h8:    rmux = out;
      4'h9:    rmux = pk;
      default: rmux = 16'd0;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Registers: all reset to 0 (D-MC-15 via the inverted encodings)
  // ---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      poly    <= 32'd0;
      val     <= 32'd0;
      wm1_x   <= 5'd0;
      reflect <= 1'b0;
      sr      <= 8'd0;
      cnt     <= 4'd0;
      en      <= 1'b0;
      rx      <= 1'b0;
      k6      <= 1'b0;
      nrzi    <= 1'b0;
      pmsb    <= 1'b0;
      run     <= 3'd0;
      ins     <= 1'b0;
      lvl_n   <= 1'b0;
      pk      <= 16'd0;
      pkn     <= 4'd0;
      out     <= 16'd0;
      outv_q  <= 1'b0;
      ovr     <= 1'b0;
      serr    <= 1'b0;
      rdata_q <= 16'd0;
    end else begin
      poly    <= n_poly;
      val     <= n_val;
      wm1_x   <= n_wm1 ^ 5'b00111;
      reflect <= n_reflect;
      sr      <= n_sr;
      cnt     <= n_cnt;
      en      <= n_en;
      rx      <= n_rx;
      k6      <= n_k6;
      nrzi    <= n_nrzi;
      pmsb    <= n_pmsb;
      run     <= n_run;
      ins     <= n_ins;
      lvl_n   <= ~n_lvl;
      pk      <= n_pk;
      pkn     <= n_pkn;
      out     <= n_out;
      outv_q  <= n_outv;
      ovr     <= n_ovr;
      serr    <= n_serr;
      if (a_req & ~a_we) rdata_q <= rmux;            // D-MC-17
    end
  end

endmodule
