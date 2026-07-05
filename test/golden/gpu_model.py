class GoldenGPUModel:
    def __init__(self, num_warps=8, threads_per_warp=4, num_regs=32):
        self.num_warps = num_warps
        self.threads_per_warp = threads_per_warp
        self.num_regs = num_regs
        
        # State
        self.pc = [0] * num_warps
        self.active_mask = [(1 << threads_per_warp) - 1] * num_warps
        
        # Register File: [warp_id][thread_id][reg_id]
        self.regfile = [[[0 for _ in range(num_regs)] for _ in range(threads_per_warp)] for _ in range(num_warps)]
        
        # Shared Memory
        self.shared_mem = [0] * 1024  # 4KB (1024 x 32-bit words)
        
        # Global Memory mapping (Address -> Data)
        self.global_mem = {}
        
    def write_reg(self, warp_id, reg_id, value, thread_mask):
        if reg_id == 0:
            return # r0 is hardwired to 0
            
        for t in range(self.threads_per_warp):
            if (thread_mask & (1 << t)):
                # If value is a list (per-thread result), use that. Otherwise broadcast.
                v = value[t] if isinstance(value, list) else value
                self.regfile[warp_id][t][reg_id] = v & 0xFFFFFFFF
                
    def read_reg(self, warp_id, reg_id):
        if reg_id == 0:
            return [0] * self.threads_per_warp
        return [self.regfile[warp_id][t][reg_id] for t in range(self.threads_per_warp)]

    def execute_add(self, warp_id, rd, rs1, rs2, thread_mask):
        vals1 = self.read_reg(warp_id, rs1)
        vals2 = self.read_reg(warp_id, rs2)
        results = [(vals1[t] + vals2[t]) & 0xFFFFFFFF for t in range(self.threads_per_warp)]
        self.write_reg(warp_id, rd, results, thread_mask)
        
    def execute_sub(self, warp_id, rd, rs1, rs2, thread_mask):
        vals1 = self.read_reg(warp_id, rs1)
        vals2 = self.read_reg(warp_id, rs2)
        results = [(vals1[t] - vals2[t]) & 0xFFFFFFFF for t in range(self.threads_per_warp)]
        self.write_reg(warp_id, rd, results, thread_mask)
        
    def execute_xor(self, warp_id, rd, rs1, rs2, thread_mask):
        vals1 = self.read_reg(warp_id, rs1)
        vals2 = self.read_reg(warp_id, rs2)
        results = [(vals1[t] ^ vals2[t]) & 0xFFFFFFFF for t in range(self.threads_per_warp)]
        self.write_reg(warp_id, rd, results, thread_mask)

    def execute_addi(self, warp_id, rd, rs1, imm, thread_mask):
        vals1 = self.read_reg(warp_id, rs1)
        results = [(vals1[t] + imm) & 0xFFFFFFFF for t in range(self.threads_per_warp)]
        self.write_reg(warp_id, rd, results, thread_mask)
        
    # Example of differential check interface
    def check_state(self, rtl_regfile, rtl_pc):
        """ Compare golden state to RTL state """
        # Implementation of comparison logic that cocotb tests will call
        pass
