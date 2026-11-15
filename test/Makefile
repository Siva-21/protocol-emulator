# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
# RTL runs default to Verilator, or Icarus if Verilator is not on PATH.
# Gate-level runs stay on Icarus. Tiny Tapeout's gl_test action installs only
# Icarus and runs `make clean` (without GATES=yes), then `GATES=yes make`, so
# the fallback keeps `make clean` working there.
ifeq ($(GATES),yes)
SIM ?= icarus
else ifneq ($(shell command -v verilator 2>/dev/null),)
SIM ?= verilator
else
SIM ?= icarus
endif
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = common/icg.v \
                  common/lword.v \
                  host_link/host_link_sync.sv \
                  host_link/host_link_ctrl.sv \
                  host_link/host_link_dp.sv \
                  host_link/host_link.sv \
                  sysbus/sysbus.v \
                  main_ss/sram_if.v \
                  main_ss/crc_bs.v \
                  main_ss/mc_core.v \
                  main_ss/main_ss.v \
                  sys_ctrl/sys_ctrl_psc.sv \
                  sys_ctrl/sys_ctrl_ctrl.sv \
                  sys_ctrl/sys_ctrl_rd.sv \
                  sys_ctrl/sys_ctrl.sv \
                  sc_pair/sc_cfg.v \
                  sc_pair/sc_bank.v \
                  sc_pair/sc_win.v \
                  sc_pair/sc_seq.v \
                  sc_pair/sc_evu.v \
                  sc_pair/sc_tmr.v \
                  sc_pair/sc_cnt.v \
                  sc_pair/sc_sa.v \
                  sc_pair/sc_sb.v \
                  sc_pair/sc_fifo_a.v \
                  sc_pair/sc_fifo_b.v \
                  sc_pair/sc_out.v \
                  sc_pair/subcore.v \
                  sc_pair/sc_pair.v \
                  pin_layer/pin_layer_in.v \
                  pin_layer/pin_layer_pad.v \
                  pin_layer/pin_layer.v \
                  common/rst_sync.v \
                  tt_um_protocol_emulator.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
# SRAM macro of main_ss: the PDK's functional model when the PDK is installed,
# else the ports-only black box (enough while no test touches the SRAM).
SRAM_MODEL_DIR = $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog
ifneq ($(wildcard $(SRAM_MODEL_DIR)/RM_IHPSG13_1P_512x16_c2_bm_bist.v),)
VERILOG_SOURCES += $(SRAM_MODEL_DIR)/RM_IHPSG13_1P_512x16_c2_bm_bist.v
VERILOG_SOURCES += $(SRAM_MODEL_DIR)/RM_IHPSG13_1P_core_behavioral_bm_bist.v
COMPILE_ARGS    += -DFUNCTIONAL
else
VERILOG_SOURCES += $(PWD)/../verification/stubs/RM_IHPSG13_1P_512x16_c2_bm_bist.v
endif

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DSIM
# Cell models for the PDK in $(PDK) (ihp-sg13cmos5l or ihp-sg13g2), e.g. sg13cmos5l_stdcell.v
PDK ?= ihp-sg13cmos5l
PDK_CELL_PREFIX = $(patsubst ihp-%,%,$(PDK))
PDK_LIBS_REF = $(PDK_ROOT)/$(PDK)/libs.ref
VERILOG_SOURCES += $(PDK_LIBS_REF)/$(PDK_CELL_PREFIX)_io/verilog/$(PDK_CELL_PREFIX)_io.v
# Newer PDK versions ship the UDP (user-defined primitive) models in a separate file
VERILOG_SOURCES += $(wildcard $(PDK_LIBS_REF)/$(PDK_CELL_PREFIX)_stdcell/verilog/$(PDK_CELL_PREFIX)_udp.v)
VERILOG_SOURCES += $(PDK_LIBS_REF)/$(PDK_CELL_PREFIX)_stdcell/verilog/$(PDK_CELL_PREFIX)_stdcell.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Verilator: tb.v has an initial block with a delay (#1) and dumps an FST waveform
ifeq ($(SIM),verilator)
EXTRA_ARGS += --timing --trace --trace-fst --trace-structs
endif

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
