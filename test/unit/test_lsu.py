import cocotb
from cocotb.triggers import Timer, RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_lsu_mshr_stall(dut):
    """ Module Verification: Load-Store Unit MSHR and Stall Logic """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.rst_n.value = 0
    dut.req_valid.value = 0
    dut.mem_rsp_valid.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Issue a load request from Warp 3
    dut.req_warp_id.value = 3
    dut.req_valid.value = 1
    dut.req_is_store.value = 0
    dut.req_funct3.value = 2 # LW
    dut.req_mask.value = 0b0001
    dut.req_addr[0].value = 0x1000
    dut.req_rd.value = 5
    await RisingEdge(dut.clk)
    
    dut.req_valid.value = 0
    
    # Wait for processing state to issue memory request
    await RisingEdge(dut.clk)
    
    # The LSU should immediately assert a stall for Warp 3
    assert dut.stall_warp_valid.value == 1, "LSU failed to assert stall!"
    assert dut.stall_warp_id.value == 3, "LSU stalled wrong warp!"
    
    # Simulate memory delay
    await ClockCycles(dut.clk, 5)
    
    # Accept memory request
    dut.mem_req_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_req_ready.value = 0
    
    await ClockCycles(dut.clk, 5)
    
    # Return data from memory
    dut.mem_rsp_valid.value = 1
    dut.mem_rsp_rdata.value = 0xDEADBEEF
    await RisingEdge(dut.clk)
    dut.mem_rsp_valid.value = 0
    
    # Wait for writeback pipeline
    await RisingEdge(dut.clk)
    
    # The LSU should unstall Warp 3
    assert dut.unstall_warp_valid.value == 1, "LSU failed to unstall the warp!"
    assert dut.unstall_warp_id.value == 3, "LSU unstalled wrong warp!"
    
    # Check that it writes the data back
    assert dut.wb_valid.value == 1, "LSU failed to trigger writeback!"
    assert int(dut.wb_data[0].value) == 0xDEADBEEF, "LSU writeback data corrupted!"
    assert dut.wb_rd.value == 5, "LSU writeback rd incorrect!"
