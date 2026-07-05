import cocotb
from cocotb.triggers import Timer, RisingEdge, ClockCycles
from cocotb.clock import Clock

@cocotb.test()
async def test_tensor_mac(dut):
    """ Module Verification: Tensor Core 4x4 MAC """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    
    dut.rst_n.value = 0
    dut.start.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Initialize matrices
    for i in range(4):
        for j in range(4):
            idx = i * 4 + j
            dut.mat_a[idx].value = i + j
            dut.mat_b[idx].value = i * j
            dut.mat_c[idx].value = 1
            
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    # Wait for completion
    for _ in range(20):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            break
            
    assert dut.done.value == 1, "Tensor core did not signal completion!"
    
    # Check one element of the result
    # D[0][0] = A[0][k]*B[k][0] + C[0][0]
    # A[0][k] = k
    # B[k][0] = 0
    # sum = 0 + C[0][0] = 1
    assert int(dut.mat_d[0].value) == 1, "Tensor MAC computed incorrectly!"
