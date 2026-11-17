// -----------------------------------------------------------------------------
// sc_seq
//
// Sequencer and run control (spec §4.3, §4.4, §4.5 EXT, §4.12 DISP, §5;
// architecture §4.1-§4.3, §4.8, §4.9): state, entry, halted, STEP and
// breakpoint; the 32 conditions, preemption, next state; the micro-op strobes
// u[31:0] and the pin codes code[3k +: 3] for outputs k = 0..5; the matcher
// and the EXT level / sticky bit.
//
// entry and halted_q are stored inverted (entry_x, halted_x) so that every
// flop resets to 0 and reset reads as state 0, entry 1, halted.
//
// Flops: state 5, entry_x 1, halted_x 1, step_q 1, bp_hit 1, ext_st 1 = 10.
// -----------------------------------------------------------------------------

`default_nettype none

module sc_seq #(
  parameter IS_MASTER = 0,
  parameter NPAT      = 5
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [31:0] instr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  wire [6:0]  ctrl,          // [3:0] used here
  /* verilator lint_on UNUSEDSIGNAL */
  input  wire        run_i,
  input  wire        halt_i,
  /* verilator lint_off UNUSEDSIGNAL */
  input  wire [1:0]  m_split_i,     // partner only (32/0 force)
  /* verilator lint_on UNUSEDSIGNAL */
  // configuration
  /* verilator lint_off UNUSEDSIGNAL */
  input  wire [13:0] seq_cfg,       // [4:0] ENTRY [7] BP_EN [12:8] BP_STATE [13] SBIT_SRC
  /* verilator lint_on UNUSEDSIGNAL */
  input  wire [9:0]  pre0,          // [0] EN [3:1] EV [8:4] VECTOR [9] ALWAYS
  input  wire [9:0]  pre1,
  input  wire [3:0]  evu_sticky,    // EVUk.STICKY
  input  wire [15:0] ext_cfg,       // [9:0] MASK [11:10] MB_SEL [14:12] SIG_SEL [15] STICKY
  input  wire [15:0] match_val,
  input  wire [15:0] match_mask,
  input  wire [6:0]  disp_cfg,      // [1:0] SRC [5:2] BASE [6] WIDTH3
  input  wire [1:0]  sa_lanes,      // SA_CFG.LANES (1/2/4/8)
  input  wire [89:0] pato,          // PATOk at [15k +: 15]
  // condition and event sources
  input  wire [3:0]  evr_e,
  input  wire        evr_t1p,
  input  wire        evr_t1c,
  input  wire        evr_t2p,
  input  wire        evr_t2c,
  input  wire        evr_err,
  input  wire [3:0]  sticky,
  input  wire        sa_valid,
  input  wire        sa_lane0,
  input  wire        sb_done,
  input  wire        sb_last,
  input  wire [15:0] sb_sr,
  input  wire        cnt_zero,
  input  wire [2:0]  fa_cnt,
  input  wire [16:0] fa_head,
  input  wire [15:0] fbnew,
  input  wire        fb_full,       // RXFULL
  input  wire        err_any,
  input  wire [3:0]  mb,
  input  wire [7:0]  sig_i,
  input  wire [15:0] in_r_i,
  // outputs
  output reg  [4:0]  state,
  output wire        entry,
  output wire        halted_eff,
  output reg         bp_hit,
  output reg         step_q,
  output wire [31:0] u,
  output reg  [17:0] code,
  output wire [3:0]  consume,
  output reg         ext_st
);

  reg entry_x, halted_x;
  assign entry = ~entry_x;
  wire halted_q = ~halted_x;

  wire srst = ctrl[3];

  // ---- run control (§4.3)
  wire force_h;
  generate
    if (IS_MASTER != 0) begin : g_m
      assign force_h = 1'b0;
    end else begin : g_p
      assign force_h = (m_split_i == 2'd2);   // 32/0 partner (D-SC-8)
    end
  endgenerate

  assign halted_eff = halted_q | force_h;
  wire running = ~halted_eff | step_q;
  wire act     = running & entry;

  // ---- instruction fields
  wire [4:0] f_cond = instr[31:27];
  wire [4:0] f_t    = instr[26:22];
  wire [4:0] f_f    = instr[21:17];
  wire       f_pe   = instr[16];
  wire [2:0] f_osel = instr[15:13];
  wire [2:0] f_pop  = instr[12:10];
  wire [4:0] f_opa  = instr[9:5];
  wire [4:0] f_opb  = instr[4:0];

  // ---- EXT (§4.5) and matcher
  wire [9:0] ext_src = {err_any, fb_full, sig_i[ext_cfg[14:12]], mb[ext_cfg[11:10]],
                        evr_t2p, evr_t1p, evr_e};
  wire ext_lvl = |(ext_src & ext_cfg[9:0]);
  wire match   = ((sb_sr ^ match_val) & match_mask) == 16'd0;

  // ---- conditions C0-C31
  wire        fa_ne = (fa_cnt != 3'd0);
  wire [15:0] c_lo = {
    ext_lvl | (ext_cfg[15] & ext_st),          // 15 EXT
    fa_ne & fa_head[16],                       // 14 TXTAG
    fa_ne,                                     // 13 TXNE
    match,                                     // 12 MATCH
    seq_cfg[13] ? sb_last : sa_lane0,          // 11 SBIT
    cnt_zero,                                  // 10 CNT0
    sb_done,                                   //  9 SBD
    ~sa_valid,                                 //  8 SAD
    evr_t2c, evr_t2p, evr_t1c, evr_t1p,        //  7..4
    evr_e | (evu_sticky & sticky)              //  3..0 E0-E3
  };
  wire [31:0] cnds = {in_r_i, c_lo};
  wire        cnd  = cnds[f_cond];

  // ---- preemption
  wire [7:0] pev  = {ext_lvl, evr_err, evr_t2p, evr_t1p, evr_e};
  wire       hit0 = pre0[0] & (pre0[9] | f_pe) & pev[pre0[3:1]];
  wire       hit1 = pre1[0] & (pre1[9] | f_pe) & pev[pre1[3:1]];

  // ---- micro-op strobes (§4.4)
  assign u = act ? ((32'd1 << f_opa) | (32'd1 << f_opb)) : 32'd0;

  // ---- DISP (§4.12)
  reg [15:0] disp_src;
  always @(*) begin
    case (disp_cfg[1:0])
      2'd0:    disp_src = sb_sr;
      2'd1:    disp_src = fbnew;
      2'd2:    disp_src = fa_head[15:0];
      default: disp_src = in_r_i;
    endcase
  end
  /* verilator lint_off UNUSEDSIGNAL */
  wire [15:0] disp_sh    = disp_src >> disp_cfg[5:2];   // bits above 15 read 0
  /* verilator lint_on UNUSEDSIGNAL */
  wire [2:0]  disp_field = disp_sh[2:0] & (disp_cfg[6] ? 3'b111 : 3'b011);

  // ---- next state
  wire [4:0] nb      = (cnd ? f_t : f_f) | (u[31] ? {2'b00, disp_field} : 5'd0);
  wire [4:0] nxt     = hit0 ? pre0[8:4] : hit1 ? pre1[8:4] : nb;
  wire       entry_n = hit0 | hit1 | (nxt != state);

  wire take = running & ~hit0 & ~hit1 & cnd;
  genvar k;
  generate
    for (k = 0; k < 4; k = k + 1) begin : g_cons
      assign consume[k] = take & (f_cond == k) & evu_sticky[k];
    end
  endgenerate
  wire consume_ext = take & (f_cond == 5'd15) & ext_cfg[15];

  wire bp_now    = running & seq_cfg[7] & entry_n & (nxt == seq_cfg[12:8]);
  wire run_src   = (ctrl[0] | run_i) & ~force_h;
  wire halt_src  = halt_i | u[28] | bp_now | (ctrl[1] & ~ctrl[0]) | force_h;
  wire halted_n  = halt_src | (halted_q & ~run_src);
  wire step_n    = ctrl[2] & halted_eff & ~run_src & ~force_h;
  wire bp_hit_n  = bp_now | (bp_hit & ~(run_src | step_n));

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= 5'd0;
      entry_x  <= 1'b0;
      halted_x <= 1'b0;
      step_q   <= 1'b0;
      bp_hit   <= 1'b0;
      ext_st   <= 1'b0;
    end else begin
      if (srst) begin                         // §4.15: SOFT_RESET overrides
        state   <= seq_cfg[4:0];
        entry_x <= 1'b0;
        ext_st  <= 1'b0;
      end else begin
        if (running) begin
          state   <= nxt;
          entry_x <= ~entry_n;
        end
        ext_st <= (ext_st | ext_lvl) & ~(consume_ext | u[20]);
      end
      halted_x <= ~halted_n;
      step_q   <= step_n;
      bp_hit   <= bp_hit_n;
    end
  end

  // ---- pin codes (§4.4)
  wire [5:0] lmask = (sa_lanes == 2'd0) ? 6'b000001 :
                     (sa_lanes == 2'd1) ? 6'b000011 :
                     (sa_lanes == 2'd2) ? 6'b001111 : 6'b111111;
  // PATOk: [2:0] PAT1 [5:3] PAT2 [8:6] PAT3 [11:9] PAT4 [14:12] PAT5
  function [2:0] pat_code;
    input [14:0] pw;
    input [2:0]  p;
    begin
      case (p)
        3'd1:    pat_code = pw[2:0];
        3'd2:    pat_code = pw[5:3];
        3'd3:    pat_code = pw[8:6];
        3'd4:    pat_code = pw[11:9];
        default: pat_code = pw[14:12];
      endcase
    end
  endfunction

  integer j;
  always @(*) begin
    code = 18'd0;
    if (act && f_pop != 3'd0) begin
      case (f_osel)
        3'd6:
          for (j = 0; j < 6; j = j + 1)
            if (lmask[j]) code[3*j +: 3] = f_pop;
        3'd7:
          for (j = 0; j < 6; j = j + 1)
            if (f_pop == 3'd6)
              code[3*j +: 3] = 3'd3;
            else if (f_pop == 3'd7)
              code[3*j +: 3] = 3'd7;
            else if ({29'd0, f_pop} <= NPAT)
              code[3*j +: 3] = pat_code(pato[15*j +: 15], f_pop);
        default:
          code[3*f_osel +: 3] = f_pop;
      endcase
    end
  end

endmodule
