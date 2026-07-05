#!/bin/bash

# Create a directory to store all detailed text logs
mkdir -p logs

echo "========================================="
echo " Phoenix-XM Comprehensive Verification   "
echo "========================================="
echo "Logs for each test will be saved to the logs/ directory."
echo ""

# Function to run a Cocotb unit test against a specific RTL module
run_unit_test() {
    RTL_TOP=$1
    PYTHON_MODULE=$2
    LOG_FILE="logs/unit_${RTL_TOP}.log"
    
    echo -n "Running unit test for $RTL_TOP... "
    # Run make clean to avoid caching top-level sim.vvp
    make clean > /dev/null 2>&1
    # Run cocotb make, redirecting all output to the log file
    make SIM=icarus TOPLEVEL=$RTL_TOP MODULE=$PYTHON_MODULE > $LOG_FILE 2>&1
    
    # Check if cocotb reported success in the log
    if grep -q "TESTS=.*PASS=.*FAIL=0" $LOG_FILE; then
        echo -e "[\033[32mOK\033[0m]"
    else
        echo -e "[\033[31mFAILED\033[0m] -> See $LOG_FILE"
    fi
}

# Function to run a full GPU integration kernel test
run_kernel_test() {
    KERNEL_NAME=$1
    PYTHON_MODULE="test.kernels.test_${KERNEL_NAME}"
    LOG_FILE="logs/kernel_${KERNEL_NAME}.log"
    
    echo -n "Running integration kernel: $KERNEL_NAME... "
    make clean > /dev/null 2>&1
    make SIM=icarus TOPLEVEL=phoenix_gpu MODULE=$PYTHON_MODULE > $LOG_FILE 2>&1
    
    if grep -q "TESTS=.*PASS=.*FAIL=0" $LOG_FILE; then
        echo -e "[\033[32mOK\033[0m]"
    else
        echo -e "[\033[31mFAILED\033[0m] -> See $LOG_FILE"
    fi
}

echo "--- Phase 2 & 4: Unit Testing ---"
run_unit_test "phoenix_alu" "test.unit.test_alu"
run_unit_test "phoenix_warp_scheduler" "test.unit.test_warp_scheduler"
run_unit_test "phoenix_decode" "test.unit.test_decode"
run_unit_test "phoenix_tensor_core" "test.unit.test_tensor_core"
run_unit_test "phoenix_lsu" "test.unit.test_lsu"
run_unit_test "phoenix_sm" "test.unit.test_pipeline_hazards"
run_unit_test "phoenix_sfu" "test.unit.test_isa_control"

echo ""
echo "--- Phase 5: Integration Kernels ---"
run_kernel_test "vecadd"
run_kernel_test "matmul"
run_kernel_test "reduction"
run_kernel_test "prefix_sum"
run_kernel_test "divergence"

echo ""
echo "Done! Check the logs/ directory for detailed output of every single test cycle."
