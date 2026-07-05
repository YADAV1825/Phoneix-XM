# Benchmark Comparison Report

## Workload Cycle Counts

| Metric / Workload | tiny-gpu | Phoenix-XM | Notes |
| :--- | :--- | :--- | :--- |
| **VecAdd (Unrolled)** | 178 | 174 | 8-element vector addition, no branches |
| **MatMul (Unrolled)** | 436 | 174 | 2×2 matmul, k-loop fully unrolled (both GPUs) |
| **MatMul (Looped)** | 491 | 870 | 2×2 matmul, dynamic loop with branches (both GPUs) |

**Phoenix-XM incurs higher overhead on branch-intensive workloads due to its deeper pipeline and current branch handling implementation."**

### Understanding the MatMul Variants
There are three MatMul variants because tiny-gpu and Phoenix-XM originally used fundamentally different assembly approaches. To achieve an apples-to-apples comparison, we run both approaches on both architectures:
- **MatMul (Unrolled):** Computes all matrix elements using a flat sequence of instructions with no loops or branches. Phoenix-XM executes this very efficiently (174 cycles) because its pipeline has no branch penalties, but tiny-gpu requires more instructions (436 cycles) to manually compute the same outputs.
- **MatMul (Looped):** Computes the matrix elements using a dynamic loop with branch instructions and index math. This requires the architectures to support branch prediction and resolution. tiny-gpu executes this in 491 cycles, while Phoenix-XM takes 870 cycles due to its multi-stage pipeline having to resolve branches dynamically.
- **Original Comparison Context:** Initially, we compared tiny-gpu's Looped MatMul to Phoenix-XM's Unrolled MatMul, which resulted in a misleading 491 vs 174 cycle count.

## Architectural Metrics

| Metric | tiny-gpu | Phoenix-XM |
| :--- | :--- | :--- |
| **Scheduler Stalls** | N/A (Support not available on this machine) | 82.8% |
| **LSU Utilization** | N/A (Support not available on this machine) | 0.0% |
| **Warp Scheduler** | N/A (Support not available on this machine) | Round-robin, 8 warps |
| **Data Width** | 8-bit | 32-bit |
| **Instruction Width** | 16-bit | 32-bit (RISC-V) |
| **Thread Parallelism** | Per-core SISD | SIMT, 4 lanes/warp |
| **Branch Support** | CMP+BRnzp | BEQ/BNE/BLT/BGE/BLTU/BGEU |

