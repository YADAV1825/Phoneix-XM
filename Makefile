SIM ?= icarus
TOPLEVEL_LANG ?= verilog
WAVES ?= 1

# If generating waveforms for Icarus
ifeq ($(SIM), icarus)
    COMPILE_ARGS += -g2012
    ifeq ($(WAVES), 1)
        COMPILE_ARGS += -s tb_dump
        VERILOG_SOURCES += $(PWD)/test/helpers/tb_dump.sv
    endif
endif

# If generating waveforms for Verilator
ifeq ($(SIM), verilator)
    COMPILE_ARGS += --trace --trace-structs -Wno-fatal
    EXTRA_ARGS += --trace
endif

# Include all RTL sources
VERILOG_SOURCES += $(PWD)/rtl/pkg/phoenix_pkg.sv
VERILOG_SOURCES += $(PWD)/rtl/cache/phoenix_l1_dcache.sv
VERILOG_SOURCES += $(PWD)/rtl/cache/phoenix_l1_icache.sv
VERILOG_SOURCES += $(PWD)/rtl/cache/phoenix_l2_cache.sv
VERILOG_SOURCES += $(PWD)/rtl/fabric/phoenix_fabric.sv
VERILOG_SOURCES += $(PWD)/rtl/fabric/phoenix_fabric_router.sv
VERILOG_SOURCES += $(PWD)/rtl/memory/phoenix_mem_controller.sv
VERILOG_SOURCES += $(PWD)/rtl/memory/phoenix_global_mem.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_alu.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_sfu.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_decode.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_fetch.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_lsu.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_regfile.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_shared_mem.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_tensor_core.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_warp_scheduler.sv
VERILOG_SOURCES += $(PWD)/rtl/sm/phoenix_sm.sv
VERILOG_SOURCES += $(PWD)/rtl/tile/phoenix_dispatcher.sv
VERILOG_SOURCES += $(PWD)/rtl/tile/phoenix_tile_crossbar.sv
VERILOG_SOURCES += $(PWD)/rtl/tile/phoenix_tile.sv
VERILOG_SOURCES += $(PWD)/rtl/phoenix_global_scheduler.sv
VERILOG_SOURCES += $(PWD)/rtl/phoenix_gpu.sv

TOPLEVEL = phoenix_gpu
MODULE ?= test.kernels.test_vecadd

# Include cocotb makefile
include $(shell cocotb-config --makefiles)/Makefile.sim

# Clean up waveform outputs
clean::
	rm -f *.vcd *.fst *.hier
