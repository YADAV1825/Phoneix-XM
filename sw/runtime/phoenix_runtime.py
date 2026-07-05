import cocotb
from cocotb.triggers import RisingEdge, Timer

class PhoenixRuntime:
    """
    Host runtime for interacting with the Phoenix-XM GPU via cocotb.
    Simulates the driver and PCIe memory-mapped interface.
    """
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk

    async def write_imem(self, tile_id: int, start_addr: int, data: list[int]):
        """Write instructions to a tile's IMEM."""
        self.dut.host_imem_wr_en.value = 1
        self.dut.host_imem_tile_id.value = tile_id
        for i, val in enumerate(data):
            self.dut.host_imem_wr_addr.value = start_addr + i * 4
            self.dut.host_imem_wr_data.value = val
            await RisingEdge(self.clk)
        self.dut.host_imem_wr_en.value = 0
        await RisingEdge(self.clk)

    async def write_dmem(self, tile_id: int, start_addr: int, data: list[int]):
        """Write 32-bit words to a tile's DMEM."""
        self.dut.host_dmem_wr_en.value = 1
        self.dut.host_dmem_tile_id.value = tile_id
        for i, val in enumerate(data):
            self.dut.host_dmem_wr_addr.value = start_addr + i * 4
            self.dut.host_dmem_wr_data.value = val
            await RisingEdge(self.clk)
        self.dut.host_dmem_wr_en.value = 0
        await RisingEdge(self.clk)

    async def read_dmem(self, tile_id: int, start_addr: int, count: int) -> list[int]:
        """Read 32-bit words from a tile's DMEM."""
        result = []
        self.dut.host_dmem_rd_en.value = 1
        self.dut.host_dmem_rd_tile_id.value = tile_id
        for i in range(count):
            self.dut.host_dmem_rd_addr.value = start_addr + i * 4
            await RisingEdge(self.clk)
            # Read after address is latched
            # Usually takes 1 cycle depending on SRAM modeling. In our simple SRAM it's comb read.
            result.append(int(self.dut.host_dmem_rd_data.value))
        self.dut.host_dmem_rd_en.value = 0
        await RisingEdge(self.clk)
        return result

    async def launch_kernel(self, tile_id: int, pc: int, num_blocks: int, threads_per_block: int):
        """Launch a kernel on a specific tile."""
        self.dut.host_kernel_valid.value = 1
        self.dut.host_kernel_tile_id.value = tile_id
        self.dut.host_kernel_pc.value = pc
        self.dut.host_kernel_num_blocks.value = num_blocks
        self.dut.host_kernel_threads_per_block.value = threads_per_block
        
        while True:
            await RisingEdge(self.clk)
            if self.dut.host_kernel_ready.value == 1:
                break
                
        self.dut.host_kernel_valid.value = 0
        await RisingEdge(self.clk)

    async def wait_kernel_done(self, timeout_cycles=1000):
        """Wait for the GPU to signal kernel completion."""
        cycles = 0
        while True:
            if self.dut.host_kernel_done.value == 1:
                return True
            await RisingEdge(self.clk)
            cycles += 1
            if cycles >= timeout_cycles:
                raise TimeoutError(f"Kernel did not finish within {timeout_cycles} cycles")
