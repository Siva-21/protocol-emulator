// -----------------------------------------------------------------------------
// subcore
//
// One sub-core (spec pe_subcore, docs/Implementation_spec/
// Subcore_Implementation_Specification.pdf v1.0; architecture §4): one state
// per clock, two micro-ops and one pin action per state, datapath running
// every clock, halted or not (SC-02). Wiring only; the logic is in the
// sub-modules (spec F1):
//
//   sc_win    bus window, xr_q, flags, latch write enables
//   sc_cfg    34 configuration words (latches)       sc_bank  program bank
//   sc_seq    sequencer, run control, conditions, strobes, EXT, DISP
//   sc_evu x4 event units                            sc_tmr x2  T1, T2
//   sc_cnt    counter                                sc_sa / sc_sb  shifters
//   sc_fifo_a / sc_fifo_b                            sc_out   output stage
//
// IS_MASTER = 1 for SC0 and SC2 (taps, own/partner 2:1, SEQ_CFG.SPLIT).
// Storage: 959 latches (957 on a partner), 324 flops (315 on a partner).
// -----------------------------------------------------------------------------

`default_nettype none

module subcore #(
  parameter IS_MASTER = 0,
  parameter FA_DEPTH  = 4,
  parameter NPAT      = 5
) (
  input  wire        clk,
  input  wire        rst_n,
  // bus target, window 0x1000 + 0x80*n
  input  wire        req_i,
  input  wire        dir_i,         // 1 = write
  input  wire [6:0]  addr_i,
  input  wire [15:0] wdata_i,
  output wire        wready_o,      // tied 1 (BUS-06)
  output wire        rready_o,      // tied 1
  output wire [15:0] rdata_o,       // xr_q, valid in the clock after a read
  // pins
  input  wire [15:0] in_i,          // IN
  input  wire [15:0] in_r_i,        // IN_R
  output wire [5:0]  q_o,
  output wire [5:0]  qoe_o,
  output wire [7:0]  tap_o,         // SA taps (IS_MASTER), else 0
  output wire        tap_oe_o,
  // sys_ctrl
  input  wire        run_i,         // RUN_MASK run strobe
  input  wire        halt_i,        // RUN_MASK halt strobe
  input  wire [2:0]  tick_i,        // prescaler ticks /16, /256, /4096
  output wire        fa_space_o,
  output wire        fb_ne_o,
  output wire        ntf_o,
  output wire        halted_o,
  output wire        err_o,
  // SIG lines
  output wire [1:0]  sig_o,
  input  wire [7:0]  sig_i,         // {sig_o of SC3, SC2, SC1, SC0}
  // pair, master side (IS_MASTER = 1)
  input  wire [31:0] p_lo_i,
  input  wire [31:0] p_hi_i,
  output wire [1:0]  split_o,
  output wire [2:0]  mstate_o,
  output wire        mheff_o,
  // pair, partner side (IS_MASTER = 0)
  input  wire [1:0]  m_split_i,
  input  wire [2:0]  m_state_i,
  input  wire        m_heff_i,
  output wire [31:0] lo_o,
  output wire [31:0] hi_o
);

  assign wready_o = 1'b1;
  assign rready_o = 1'b1;

  // ---- configuration words
  /* verilator lint_off UNUSEDSIGNAL */
  wire [543:0] cfg;
  /* verilator lint_on UNUSEDSIGNAL */
  wire [15:0] t1_per   = cfg[16*0  +: 16];
  wire [15:0] t1_cmp   = cfg[16*1  +: 16];
  wire [11:0] t1_ctl   = cfg[16*2  +: 12];
  wire [7:0]  t1_frac  = cfg[16*3  +: 8];
  wire [15:0] t2_per   = cfg[16*4  +: 16];
  wire [15:0] t2_cmp   = cfg[16*5  +: 16];
  wire [11:0] t2_ctl   = cfg[16*6  +: 12];
  wire [15:0] cnt_pre  = cfg[16*7  +: 16];
  wire [8:0]  cnt_ctl  = cfg[16*8  +: 9];
  wire [15:0] mval     = cfg[16*9  +: 16];
  wire [15:0] mmask    = cfg[16*10 +: 16];
  wire [13:0] sa_cfg   = cfg[16*11 +: 14];
  wire [14:0] sb_cfg   = cfg[16*12 +: 15];
  wire [15:0] ext_cfg  = cfg[16*23 +: 16];
  wire [13:0] seq_cfg  = cfg[16*24 +: 14];
  wire [6:0]  disp_cfg = cfg[16*25 +: 7];
  wire [9:0]  pre0     = cfg[16*26 +: 10];
  wire [9:0]  pre1     = cfg[16*27 +: 10];
  wire [51:0] evu_cfg;              // EVUk at [13k +: 13]
  wire [65:0] out_cfg;              // OUTk at [11k +: 11]
  wire [89:0] pato;                 // PATOk at [15k +: 15]
  genvar k;
  generate
    for (k = 0; k < 4; k = k + 1) begin : g_evu_cfg
      assign evu_cfg[13*k +: 13] = cfg[16*(13+k) +: 13];
    end
    for (k = 0; k < 6; k = k + 1) begin : g_out_cfg
      assign out_cfg[11*k +: 11] = cfg[16*(17+k) +: 11];
      assign pato[15*k +: 15]    = cfg[16*(28+k) +: 15];
    end
  endgenerate

  // ---- interconnect
  wire        wr, rd;
  wire [6:0]  ctrl;
  wire [33:0] cfg_en;
  wire [31:0] row_en;
  wire [15:0] xr_q;
  wire [2:0]  err, ntf;
  wire [3:0]  mb;
  wire [1:0]  sig;
  wire        evr_err;

  wire [4:0]  state;
  wire        entry, halted_eff, bp_hit, step_q, ext_st;
  /* verilator lint_off UNUSEDSIGNAL */
  wire [31:0] u;                    // [0] NOP; [20] [28] [31] used in sc_seq
  /* verilator lint_on UNUSEDSIGNAL */
  wire [31:0] instr;
  wire [17:0] code;
  wire [3:0]  consume;

  wire [3:0]  evr_e, sticky;
  wire        evr_t1p, evr_t1c, evr_t2p, evr_t2c, clk1, clk2;
  wire [15:0] t1_cnt, t2_cnt;

  wire [15:0] cnt;
  wire        cnt_zero, burst_end, fa_empty_set;

  wire [15:0] sa_sr;
  wire        sa_valid, sa_pop, sa_shifted;
  wire [8:0]  lane;

  wire [15:0] sb_sr, req0_d;
  wire        sb_done, sb_last, sb_cap, req0;

  wire [2:0]  fa_cnt;
  wire [16:0] fa_head;
  wire        fa_ne, fa_ovr_set;

  wire [1:0]  fb_cnt;
  wire [16:0] fb_head;
  wire [15:0] fbnew;
  wire        fb_full, fb_ovr_set;

  wire srst = ctrl[3];

  // ---- sub-modules
  sc_win #(.IS_MASTER(IS_MASTER)) u_win (
    .clk(clk), .rst_n(rst_n),
    .req_i(req_i), .dir_i(dir_i), .addr_i(addr_i), .wdata_i(wdata_i), .xr_q(xr_q),
    .wr(wr), .rd(rd), .ctrl(ctrl), .cfg_en(cfg_en), .row_en(row_en),
    .halted_eff(halted_eff), .m_heff_i(m_heff_i), .m_split_i(m_split_i),
    .fa_empty_set(fa_empty_set), .fb_ovr_set(fb_ovr_set), .fa_ovr_set(fa_ovr_set),
    .u_ntf(u[25:23]), .u_sig(u[22:21]),
    .err(err), .ntf(ntf), .mb(mb), .sig(sig), .evr_err(evr_err),
    .state(state), .entry(entry), .bp_hit(bp_hit),
    .fb_head(fb_head), .fb_cnt(fb_cnt), .fa_cnt(fa_cnt), .fa_head(fa_head),
    .ext_st(ext_st), .sticky(sticky),
    .cnt(cnt), .t1_cnt(t1_cnt), .t2_cnt(t2_cnt), .sa_sr(sa_sr), .sb_sr(sb_sr),
    .evr_e(evr_e), .evr_t1p(evr_t1p), .evr_t1c(evr_t1c), .evr_t2p(evr_t2p), .evr_t2c(evr_t2c)
  );

  sc_cfg #(.IS_MASTER(IS_MASTER)) u_cfg (
    .clk(clk), .rst_n(rst_n), .en(cfg_en), .d(xr_q), .cfg_o(cfg)
  );

  sc_bank #(.IS_MASTER(IS_MASTER)) u_bank (
    .clk(clk), .rst_n(rst_n), .row_en(row_en), .d(xr_q), .state(state),
    .m_split_i(m_split_i), .m_state_i(m_state_i), .p_lo_i(p_lo_i), .p_hi_i(p_hi_i),
    .lo_o(lo_o), .hi_o(hi_o), .instr(instr)
  );

  sc_seq #(.IS_MASTER(IS_MASTER), .NPAT(NPAT)) u_seq (
    .clk(clk), .rst_n(rst_n), .instr(instr), .ctrl(ctrl), .run_i(run_i), .halt_i(halt_i),
    .m_split_i(m_split_i),
    .seq_cfg(seq_cfg), .pre0(pre0), .pre1(pre1),
    .evu_sticky({evu_cfg[13*3+6], evu_cfg[13*2+6], evu_cfg[13*1+6], evu_cfg[6]}),
    .ext_cfg(ext_cfg), .match_val(mval), .match_mask(mmask), .disp_cfg(disp_cfg),
    .sa_lanes(sa_cfg[6:5]), .pato(pato),
    .evr_e(evr_e), .evr_t1p(evr_t1p), .evr_t1c(evr_t1c), .evr_t2p(evr_t2p), .evr_t2c(evr_t2c),
    .evr_err(evr_err), .sticky(sticky),
    .sa_valid(sa_valid), .sa_lane0(lane[0]), .sb_done(sb_done), .sb_last(sb_last), .sb_sr(sb_sr),
    .cnt_zero(cnt_zero), .fa_cnt(fa_cnt), .fa_head(fa_head), .fbnew(fbnew), .fb_full(fb_full),
    .err_any(|err), .mb(mb), .sig_i(sig_i), .in_r_i(in_r_i),
    .state(state), .entry(entry), .halted_eff(halted_eff), .bp_hit(bp_hit), .step_q(step_q),
    .u(u), .code(code), .consume(consume), .ext_st(ext_st)
  );

  generate
    for (k = 0; k < 4; k = k + 1) begin : g_evu
      /* verilator lint_off UNUSEDSIGNAL */
      wire [12:0] ec = evu_cfg[13*k +: 13];         // [6] STICKY used in sc_seq
      /* verilator lint_on UNUSEDSIGNAL */
      sc_evu u_evu (
        .clk(clk), .rst_n(rst_n), .srst(srst), .in_i(in_i), .in_r_i(in_r_i),
        .pin(ec[3:0]), .mode(ec[5:4]), .qen(ec[7]), .qpin(ec[11:8]), .qlvl(ec[12]),
        .consume(consume[k]), .clr(u[16+k]), .evr_e(evr_e[k]), .sticky(sticky[k])
      );
    end
  endgenerate

  /* verilator lint_off PINCONNECTEMPTY */
  sc_tmr #(.IS_T1(1)) u_t1 (
    .clk(clk), .rst_n(rst_n), .srst(srst), .per(t1_per), .cmp(t1_cmp), .ctl(t1_ctl),
    .frac(t1_frac), .tick_i(tick_i), .go(u[8]), .stop_u(u[9]), .evr_e(evr_e),
    .oth_p(evr_t2p), .oth_c(evr_t2c), .burst_end(burst_end), .cnt_zero(cnt_zero),
    .evr_p(evr_t1p), .evr_c(evr_t1c), .clk_o(clk1), .cnt_dbg(t1_cnt)
  );

  sc_tmr #(.IS_T1(0)) u_t2 (
    .clk(clk), .rst_n(rst_n), .srst(srst), .per(t2_per), .cmp(t2_cmp), .ctl(t2_ctl),
    .frac(8'd0), .tick_i(tick_i), .go(u[10]), .stop_u(u[11]), .evr_e(evr_e),
    .oth_p(evr_t1p), .oth_c(evr_t1c), .burst_end(burst_end), .cnt_zero(cnt_zero),
    .evr_p(evr_t2p), .evr_c(evr_t2c), .clk_o(clk2), .cnt_dbg(t2_cnt)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  sc_cnt u_cnt (
    .clk(clk), .rst_n(rst_n), .srst(srst),
    .u_ldp(u[12]), .u_ldf(u[13]), .u_ldb(u[14]), .u_dec(u[15]), .u_inc(u[29]),
    .pre(cnt_pre), .ctl(cnt_ctl), .evr_e(evr_e), .evr_t1p(evr_t1p), .evr_t2p(evr_t2p),
    .sa_shifted(sa_shifted), .sb_cap(sb_cap), .fa_ne(fa_ne), .fa_head(fa_head[15:0]),
    .sb_sr(sb_sr), .cnt(cnt), .cnt_zero(cnt_zero), .burst_end(burst_end),
    .fa_empty_set(fa_empty_set)
  );

  sc_sa u_sa (
    .clk(clk), .rst_n(rst_n), .srst(srst),
    .u_load(u[1]), .u_step(u[2]), .u_stop(u[3]), .cfg(sa_cfg),
    .evr_e(evr_e), .evr_t1p(evr_t1p), .evr_t1c(evr_t1c), .evr_t2p(evr_t2p), .evr_t2c(evr_t2c),
    .fa_ne(fa_ne), .fa_head(fa_head[15:0]),
    .sa_sr(sa_sr), .sa_valid(sa_valid), .lane(lane), .sa_pop(sa_pop), .sa_shifted(sa_shifted)
  );

  sc_sb u_sb (
    .clk(clk), .rst_n(rst_n), .srst(srst),
    .u_arm(u[4]), .u_step(u[5]), .u_push(u[6]), .u_stop(u[7]), .cfg(sb_cfg),
    .evr_e(evr_e), .evr_t1p(evr_t1p), .evr_t1c(evr_t1c), .evr_t2p(evr_t2p), .evr_t2c(evr_t2c),
    .in_r_i(in_r_i),
    .sb_sr(sb_sr), .sb_done(sb_done), .sb_last(sb_last), .sb_cap(sb_cap),
    .req0(req0), .req0_d(req0_d)
  );

  sc_fifo_a #(.FA_DEPTH(FA_DEPTH)) u_fa (
    .clk(clk), .rst_n(rst_n), .clr(ctrl[4] | srst), .wr(wr), .addr_i(addr_i), .wdata_i(wdata_i),
    .sa_pop(sa_pop), .u_skip(u[27]), .u_load(u[1]), .u_ldf(u[13]), .u_ldp(u[12]),
    .fa_cnt(fa_cnt), .fa_head(fa_head), .fa_ne(fa_ne), .fa_ovr_set(fa_ovr_set)
  );

  sc_fifo_b u_fb (
    .clk(clk), .rst_n(rst_n), .clr(ctrl[5] | srst), .rd(rd), .addr_i(addr_i),
    .req0(req0), .req0_d(req0_d), .u_mark(u[26]), .state(state), .u_cap(u[30]), .cnt(cnt),
    .fb_cnt(fb_cnt), .fb_head(fb_head), .fbnew(fbnew), .fb_full(fb_full), .fb_ovr_set(fb_ovr_set)
  );

  sc_out #(.IS_MASTER(IS_MASTER)) u_out (
    .clk(clk), .rst_n(rst_n), .srst(srst), .code(code), .ocfg(out_cfg), .lane(lane),
    .clk1(clk1), .clk2(clk2), .sb_last(sb_last), .in_r_i(in_r_i),
    .e0_pin(evu_cfg[3:0]), .e1_pin(evu_cfg[13 +: 4]),
    .q_o(q_o), .qoe_o(qoe_o), .tap_o(tap_o), .tap_oe_o(tap_oe_o)
  );

  // ---- status and pair outputs
  assign rdata_o    = xr_q;
  assign sig_o      = sig;
  assign fa_space_o = (fa_cnt < FA_DEPTH);
  assign fb_ne_o    = (fb_cnt != 2'd0);
  assign ntf_o      = |ntf;
  assign halted_o   = halted_eff;
  assign err_o      = |err;

  generate
    if (IS_MASTER != 0) begin : g_m
      assign split_o  = seq_cfg[6:5];
      assign mstate_o = state[2:0];
      assign mheff_o  = halted_eff;
    end else begin : g_p
      assign split_o  = 2'd0;
      assign mstate_o = 3'd0;
      assign mheff_o  = 1'b0;
    end
  endgenerate

  // step_q is internal to run control
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ok = step_q;
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
