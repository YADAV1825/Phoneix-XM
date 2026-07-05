import cocotb
from cocotb.triggers import Timer, RisingEdge, ClockCycles
from cocotb.clock import Clock
import random

@cocotb.test()
async def test_isa_memory_load_store(dut):
    """ ISA Verification: Verify LW (Load Word) and SW (Store Word) semantics """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.rst_n.value = 0
    dut.req_valid.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Test Store Word (SW)
    dut.req_warp_id.value = 0
    dut.req_mask.value = 0b0001 # Lane 0 only
    dut.req_valid.value = 1
    dut.req_is_store.value = 1
    dut.req_funct3.value = 2 # F3_SW
    dut.req_addr[0].value = 0x8000
    dut.req_wdata[0].value = 0xCAFEBABE
    
    await RisingEdge(dut.clk)
    dut.req_valid.value = 0
    
    # Wait for processing state to issue memory request
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    assert dut.mem_req_valid.value == 1, "SW did not assert memory request!"
    assert dut.mem_req_is_write.value == 1, "SW did not assert write!"
    assert int(dut.mem_req_wdata.value) == 0xCAFEBABE, "SW wrote incorrect data!"
    assert int(dut.mem_req_addr.value) == 0x8000, "SW wrote to incorrect address!"
    assert int(dut.mem_req_byte_en.value) == 0xF, "SW byte enable is incorrect!"
    
    # Acknowledge the memory request
    dut.mem_req_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_req_ready.value = 0
    
    await ClockCycles(dut.clk, 5)
    
    # Test Load Word (LW)
    dut.req_mask.value = 0b0010 # Lane 1 only
    dut.req_valid.value = 1
    dut.req_is_store.value = 0
    dut.req_funct3.value = 2 # F3_LW
    dut.req_addr[1].value = 0x9000
    
    await RisingEdge(dut.clk)
    dut.req_valid.value = 0
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    assert dut.mem_req_valid.value == 1, "LW did not assert memory request!"
    assert dut.mem_req_is_write.value == 0, "LW asserted write!"
    assert int(dut.mem_req_addr.value) == 0x9000, "LW read from incorrect address!"
    
    dut.mem_req_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_req_ready.value = 0
    
    # Provide memory response
    dut.mem_rsp_valid.value = 1
    dut.mem_rsp_rdata.value = 0xDEADBEEF
    await RisingEdge(dut.clk)
    dut.mem_rsp_valid.value = 0
    
    # Wait for writeback
    await RisingEdge(dut.clk)
    assert dut.wb_valid.value == 1, "LW did not trigger writeback!"
    assert int(dut.wb_data[1].value) == 0xDEADBEEF, "LW writeback data incorrect!"
