import cocotb
from cocotb.triggers import Timer, RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_sm_pipeline_startup(dut):
    """ Module Verification: SM Pipeline Startup Hazard """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.rst_n.value = 0
    dut.dispatch_valid.value = 0
    dut.imem_rsp_valid.value = 0
    dut.dmem_rsp_valid.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    dut.dispatch_valid.value = 1
    dut.dispatch_pc.value = 0
    dut.dispatch_block_id.value = 0
    dut.dispatch_thread_count.value = 1
    await RisingEdge(dut.clk)
    dut.dispatch_valid.value = 0
    
    # Just run a few cycles to ensure no immediate crashes
    await ClockCycles(dut.clk, 10)
    
    # Since we are not providing imem_rsp_valid, the SM will be stuck fetching.
    # This just validates the reset and dispatch wiring.
    assert dut.imem_req_valid.value == 1, "SM did not request instructions!"
