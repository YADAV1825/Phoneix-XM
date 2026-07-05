import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os

sys.path.append(os.getcwd())
from sw.assembler.phoenix_asm import assemble

async def load_program(dut, program):
    dut.host_imem_wr_en.value = 1
    dut.host_imem_tile_id.value = 0
    for i, inst in enumerate(program):
        dut.host_imem_wr_addr.value = i
        dut.host_imem_wr_data.value = inst
        await RisingEdge(dut.clk)
    dut.host_imem_wr_en.value = 0
    await RisingEdge(dut.clk)

async def load_data(dut, data_list):
    dut.host_dmem_wr_en.value = 1
    dut.host_dmem_tile_id.value = 0
    for i, data in enumerate(data_list):
        dut.host_dmem_wr_addr.value = i
        dut.host_dmem_wr_data.value = data
        await RisingEdge(dut.clk)
    dut.host_dmem_wr_en.value = 0
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_vecadd(dut):
    """ Integration Verification: Vector Addition Real Benchmark """
    # 1. Start Clock
    cocotb.start_soon(Clock(dut.clk, 2, units="ns").start())

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

    # 3. Assemble VecAdd Program
    # A unrolled vector addition for benchmarking
    # We'll just do 8 element vector addition
    # Matrix A at base 0, Matrix B at base 8, Output at 16
    asm_source = [
        "li x4, 0",     # base A
        "li x5, 8",     # base B
        "li x6, 16",    # base C
    ]
    # Unroll 8 elements
    for i in range(8):
        asm_source.extend([
            f"lw x7, {i*4}(x4)",
            f"lw x8, {i*4}(x5)",
            f"add x9, x7, x8",
            f"sw x9, {i*4}(x6)",
        ])
    asm_source.append("ret")
    
    program = assemble(asm_source)
    await load_program(dut, program)

    # 4. Load Data
    data_a = [0, 1, 2, 3, 4, 5, 6, 7]
    data_b = [0, 1, 2, 3, 4, 5, 6, 7]
    # In Phoenix-XM, addresses for DMEM in words?
    # Our data memory is word-addressed in the tile? Let's assume word-addressed.
    await load_data(dut, data_a + data_b + [0]*8)

    # 5. Launch Kernel
    dut.host_kernel_pc.value = 0
    dut.host_kernel_num_blocks.value = 1
    dut.host_kernel_threads_per_block.value = 4 # 1 Warp (THREADS_PER_WARP = 4)
    dut.host_kernel_tile_id.value = 0
    
    dut.host_kernel_valid.value = 1
    await RisingEdge(dut.clk)
    while dut.host_kernel_ready.value == 0:
        await RisingEdge(dut.clk)
    dut.host_kernel_valid.value = 0

    # 6. Wait for Completion & Count Cycles
    cycles = 0
    lsu_active_cycles = 0
    sched_stall_cycles = 0
    
    # Wait until done
    while dut.host_kernel_done.value == 0:
        await RisingEdge(dut.clk)
        cycles += 1
        
        # Track metrics by sampling internal signals
        # Tile 0, SM 0
        sm0 = dut.tiles[0].tile_inst.sms[0].sm_inst
        
        # Check if LSU is doing something (state != 0 means not idle)
        try:
            if sm0.lsu.state.value != 0:
                lsu_active_cycles += 1
        except Exception:
            pass # Just in case state is inaccessible

            
        # Check if scheduler is stalled (valid warp but no fetch)
        # simplified check: if any warp is active but we aren't fetching
        if sm0.all_warps_done.value == 0 and sm0.fetch_valid.value == 0:
            sched_stall_cycles += 1

        if cycles > 1000:
            dut._log.error("Timeout! Kernel did not finish.")
            break

    lsu_util = (lsu_active_cycles / cycles) * 100 if cycles > 0 else 0
    stall_rate = (sched_stall_cycles / cycles) * 100 if cycles > 0 else 0
    
    dut._log.info(f"Completed VecAdd in {cycles} cycles")
    dut._log.info(f"LSU Active: {lsu_active_cycles} cycles ({lsu_util:.1f}%)")
    dut._log.info(f"Scheduler Stalled: {sched_stall_cycles} cycles ({stall_rate:.1f}%)")
    
    # 7. Verification
    dut.host_dmem_rd_en.value = 1
    dut.host_dmem_rd_tile_id.value = 0
    for i in range(8):
        dut.host_dmem_rd_addr.value = 16 + i
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk) # memory latency maybe?
        val = int(dut.host_dmem_rd_data.value)
        expected = data_a[i] + data_b[i]
        # dut._log.info(f"Index {i}: {val} == {expected}")
