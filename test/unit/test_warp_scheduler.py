import cocotb
from cocotb.triggers import Timer, RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_scheduler_round_robin(dut):
    """ Module Verification: Warp Scheduler Round Robin & Stalls """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.rst_n.value = 0
    dut.launch_valid.value = 0
    dut.pipeline_ready.value = 0
    dut.stall_warp_valid.value = 0
    dut.unstall_warp_valid.value = 0
    dut.retire_warp_valid.value = 0
    dut.pc_update_valid.value = 0
    dut.mask_update_valid.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Launch Warps 0, 1, 2
    for i in range(3):
        dut.launch_valid.value = 1
        dut.launch_warp_id.value = i
        dut.launch_pc.value = 0x1000 + i * 0x100
        dut.launch_mask.value = 0xF
        await RisingEdge(dut.clk)
    dut.launch_valid.value = 0
    
    # Now enable scheduling
    dut.pipeline_ready.value = 1
    
    # The output 'sched_valid' and 'sched_warp_id' are combinational
    # Since rr_ptr=0, warp 0 should be scheduled first
    await Timer(1, units="ns")
    assert dut.sched_valid.value == 1
    assert int(dut.sched_warp_id.value) == 0
    
    # At next rising edge, warp 0 goes to FETCHING, rr_ptr advances to 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert dut.sched_valid.value == 1
    assert int(dut.sched_warp_id.value) == 1
    
    # At next rising edge, warp 1 goes to FETCHING, rr_ptr advances to 2
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert dut.sched_valid.value == 1
    assert int(dut.sched_warp_id.value) == 2
