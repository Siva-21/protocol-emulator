# Integrated Tiny Tapeout top (tt_um_protocol_emulator): every RTL file it needs,
# in the order of the former info.yaml source_files, paths from the repo root.
# Checked by rtl-checks as a unit; not hardened (see src/README.md).
src/common/icg.v
src/common/lword.v
src/host_link/host_link_sync.sv
src/host_link/host_link_ctrl.sv
src/host_link/host_link_dp.sv
src/host_link/host_link.sv
src/sysbus/sysbus.v
src/main_ss/sram_if.v
src/main_ss/crc_bs.v
src/main_ss/mc_core.v
src/main_ss/main_ss.v
src/sys_ctrl/sys_ctrl_psc.sv
src/sys_ctrl/sys_ctrl_ctrl.sv
src/sys_ctrl/sys_ctrl_rd.sv
src/sys_ctrl/sys_ctrl.sv
src/sc_pair/sc_cfg.v
src/sc_pair/sc_bank.v
src/sc_pair/sc_win.v
src/sc_pair/sc_seq.v
src/sc_pair/sc_evu.v
src/sc_pair/sc_tmr.v
src/sc_pair/sc_cnt.v
src/sc_pair/sc_sa.v
src/sc_pair/sc_sb.v
src/sc_pair/sc_fifo_a.v
src/sc_pair/sc_fifo_b.v
src/sc_pair/sc_out.v
src/sc_pair/subcore.v
src/sc_pair/sc_pair.v
src/pin_layer/pin_layer_in.v
src/pin_layer/pin_layer_pad.v
src/pin_layer/pin_layer.v
src/common/rst_sync.v
src/tt_um_protocol_emulator/tt_um_protocol_emulator.v
