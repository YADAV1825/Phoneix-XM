// ============================================================================
// Phoenix-XM GPU — Special Function Unit (SFU)
// ============================================================================
// Handles warp control and synchronization instructions:
//   - TMC (Thread Mask Control)
//   - WSPAWN (Warp Spawn)
//   - SPLIT (IPDOM branch divergence push)
//   - JOIN (IPDOM branch divergence pop)
//   - BAR (Barrier synchronization)
//
// Currently a stub for simulation validation.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module phoenix_sfu
    import phoenix_pkg::*;
#(
    parameter THREADS_PER_WARP_P = THREADS_PER_WARP
) (
    input  wire clk,
    input  wire rst_n,

    input  wire                            valid,
    input  wire [2:0]                      funct3,
    input  wire [$clog2(NUM_WARPS)-1:0]    warp_id,
    input  wire [THREADS_PER_WARP_P-1:0]   active_mask,
    input  wire [DATA_WIDTH-1:0]           rs1_data [THREADS_PER_WARP_P],
    input  wire [DATA_WIDTH-1:0]           rs2_data [THREADS_PER_WARP_P],

    output logic                           done,
    output logic                           stall_req,
    output logic                           mask_update_valid,
    output logic [$clog2(NUM_WARPS)-1:0]   mask_update_warp_id,
    output logic [THREADS_PER_WARP_P-1:0]  mask_update_value
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            stall_req <= 1'b0;
            mask_update_valid <= 1'b0;
            mask_update_warp_id <= '0;
            mask_update_value <= '0;
        end else begin
            done <= 1'b0;
            mask_update_valid <= 1'b0;

            if (valid) begin
                case (funct3)
                    F3_TMC: begin
                        // Simplified TMC: Update active mask based on rs1 of lane 0
                        mask_update_valid <= 1'b1;
                        mask_update_warp_id <= warp_id;
                        mask_update_value <= rs1_data[0][THREADS_PER_WARP_P-1:0];
                        done <= 1'b1;
                    end
                    // Other instructions not fully implemented in this prototype
                    default: begin
                        done <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
