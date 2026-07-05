import cocotb
from cocotb.triggers import Timer, RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_sfu_tmc(dut):
    """ ISA Verification: Verify TMC (Thread Mask Control) via SFU """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.rst_n.value = 0
    dut.valid.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # TMC updates the active mask to the value of rs1 from lane 0.
    dut.valid.value = 1
    dut.funct3.value = 0 # F3_TMC
    dut.warp_id.value = 2
    dut.rs1_data[0].value = 0b1010
    
    await RisingEdge(dut.clk)
    dut.valid.value = 0
    
    await Timer(1, units="ns")
    assert dut.done.value == 1, "SFU did not assert done for TMC"
    assert dut.mask_update_valid.value == 1, "SFU did not update mask"
    assert dut.mask_update_warp_id.value == 2, "TMC updated wrong warp"
    assert int(dut.mask_update_value.value) == 0b1010, "TMC updated mask with wrong value"
