# Phoenix-XM Roadmap

This document outlines the planned evolution of the Phoenix-XM architecture.

## Phase 1: Foundation (Current)

### v0.1 - The Base Core
- Basic 6-stage pipeline (Schedule, Fetch, Decode, Issue, Execute, Commit).
- RV32IM instruction decoding.
- Simple Python Assembler.
- Single block execution.

### v0.2 - Pipeline Robustness
- Hazard detection.
- Operand forwarding.
- IPDOM stack for branch divergence (if/else correctness).

### v0.3 - The Warp Scheduler
- Zero-cycle context switching.
- MSHR integration (stall on load, unstall on data return).
- Round-robin warp arbitration.

## Phase 2: Compute & Memory

### v0.4 - Tensor Core
- Integer 4x4 Systolic Array implementation.
- `TMMA` (Tensor Matrix Multiply-Accumulate) instruction.
- INT8 datatype support.

### v0.5 - The Cache Hierarchy
- Banked Shared Memory (Scratchpad).
- L1 Instruction Cache.
- L1 Data Cache (Write-through).
- Basic coherency protocols.

## Phase 3: Scaling Out

### v0.6 - The Compute Tile
- Integrating 4 SMs into a single Tile.
- Shared L2 Cache via Tile Crossbar.
- Local Tile Dispatcher for block distribution.

### v0.7 - Multiple Tiles
- Top-level GPU wrapper.
- Global Scheduler.
- Basic electrical fabric interconnect between Tiles.

## Phase 4: The Virtual Monolithic GPU

### v1.0 - Virtual GPU Software Model
- Unified memory addressing across Tiles.
- Locality-aware block dispatching.
- Full runtime driver simulation.

### v2.0 - Optical Interconnect Fabric
- Exploration of Photonic NoC (Network on Chip) topologies.
- Replacing electrical routers with simulated optical switches.
- High-bandwidth, low-latency inter-tile memory routing.
