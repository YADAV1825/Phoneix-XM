import sys
import os
import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

# Add the sw path to sys.path so we can import our assembler and runtime
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'sw'))
from assembler.phoenix_asm import assemble
from runtime.phoenix_runtime import PhoenixRuntime

@cocotb.test()
async def test_vecadd(dut):
    """Test vector addition on a single tile."""
    # 1. Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # 2. Reset
    dut.rst_n.value = 0
    dut.host_kernel_valid.value = 0
    dut.host_imem_wr_en.value = 0
    dut.host_dmem_wr_en.value = 0
    dut.host_dmem_rd_en.value = 0
    
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    runtime = PhoenixRuntime(dut, dut.clk)

    # 3. Vector Add Kernel Assembly
    # We want to do: C[i] = A[i] + B[i]
    # For simplicity, each thread will just add a constant right now,
    # or load from A, load from B, add, store to C.
    # Let's write the kernel.
    
    # Base addresses (hardcoded for now):
    # A is at 0x100
    # B is at 0x200
    # C is at 0x300
    
    asm_source = [
        # In a real kernel, we'd use thread/block IDs. 
        # For now, let's just make it very simple to verify the pipeline.
        "li x1, 0",      # i = 0 (we'll just use a loop or fixed addresses)
        
        # Let's do a simple 4-element load/add/store just to see it work.
        # Since memory addresses are byte-addressed, and we load words:
        # A[0] at 256
        "li x10, 256",   # Addr A
        "li x11, 512",   # Addr B
        "li x12, 768",   # Addr C
        
        "lw x2, 0(x10)", # load A
        "lw x3, 0(x11)", # load B
        "add x4, x2, x3",# A + B
        "sw x4, 0(x12)", # store C
        
        "ret"            # end kernel
    ]
    
    program = assemble(asm_source)
    
    # 4. Load program into Tile 0
    await runtime.write_imem(tile_id=0, start_addr=0, data=program)
    
    # 5. Load Data into Tile 0 DMEM
    data_A = [10]
    data_B = [20]
    
    await runtime.write_dmem(tile_id=0, start_addr=256, data=data_A)
    await runtime.write_dmem(tile_id=0, start_addr=512, data=data_B)
    
    # 6. Launch Kernel
    cocotb.log.info("Launching kernel...")
    await runtime.launch_kernel(tile_id=0, pc=0, num_blocks=1, threads_per_block=4)
    
    # 7. Wait for done
    cocotb.log.info("Waiting for completion...")
    await runtime.wait_kernel_done(timeout_cycles=500)
    
    # 8. Read back results
    result = await runtime.read_dmem(tile_id=0, start_addr=768, count=1)
    
    cocotb.log.info(f"Result: {result[0]}")
    assert result[0] == 30, f"Expected 30, got {result[0]}"
    
    cocotb.log.info("Test passed!")
