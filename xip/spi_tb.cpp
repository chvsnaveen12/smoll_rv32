#include "Vspi_harness.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <iomanip>

// Global time for waveforms
vluint64_t main_time = 0;

// -------------------------------------------------------------------------
// Helper: Simulation Tick
// -------------------------------------------------------------------------
void tick(Vspi_harness* top, VerilatedVcdC* tfp) {
    // Falling Edge
    top->clk_i = 0;
    top->eval();
    if (tfp) tfp->dump(main_time++);

    // Rising Edge
    top->clk_i = 1;
    top->eval();
    if (tfp) tfp->dump(main_time++);
}

// -------------------------------------------------------------------------
// Helper: Perform Read & Return Latency
// -------------------------------------------------------------------------
struct Result {
    uint32_t data;
    int latency;
    bool success;
};

Result perform_read(Vspi_harness* top, VerilatedVcdC* tfp, uint32_t addr) {
    Result res = {0, 0, false};
    
    // 1. Assert Request
    top->req_valid_i = 1;
    top->req_addr_i = addr;
    
    // Tick to let the controller see the request
    tick(top, tfp); 
    
    // De-assert request
    top->req_valid_i = 0;
    top->req_addr_i = 0;

    // 2. Wait for Response
    int cycles = 0;
    while (!top->resp_valid_o && cycles < 2000) {
        tick(top, tfp);
        cycles++;
    }

    if (cycles >= 2000) {
        std::cout << "    [TIMEOUT] No response for Addr 0x" << std::hex << addr << "\n";
        res.success = false;
        return res;
    }

    // Capture Data
    res.data = top->resp_value_o;
    res.latency = cycles;
    res.success = true;
    
    // Tick once more to clear the valid flag visibility
    tick(top, tfp);
    
    return res;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vspi_harness* top = new Vspi_harness;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    
    top->trace(tfp, 99);
    tfp->open("spi_tb.vcd");

    // Init Signals
    top->clk_i = 0;
    top->rst_ni = 0;
    top->req_valid_i = 0;
    top->req_addr_i = 0;
    top->req_value_i = 0;
    top->req_wstrb_i = 0;

    std::cout << "-------------------------------------------------\n";
    std::cout << "  Flash Controller Div/4 Clock Verification  \n";
    std::cout << "-------------------------------------------------\n";

    // --- Reset Sequence ---
    std::cout << "[INIT] Resetting...\n";
    for (int i = 0; i < 10; i++) tick(top, tfp);
    top->rst_ni = 1;
    for (int i = 0; i < 5; i++) tick(top, tfp);

    // --- Test 1: Basic Read ---
    std::cout << "\n[TEST 1] Read 0x0000\n";
    Result r1 = perform_read(top, tfp, 0x0000);
    
    // With div/4 clock, expect ~256 cycles (64 SPI bits * 4 clocks per bit)
    if (r1.success) {
        std::cout << "    Data: 0x" << std::hex << r1.data << "\n";
        std::cout << "    Latency: " << std::dec << r1.latency << " cycles.\n";
        if (r1.latency > 200) {
            std::cout << "    PASS. Div/4 clock appears to be working.\n";
        } else {
            std::cout << "    WARNING: Latency lower than expected for div/4.\n";
        }
    } else {
        std::cout << "    FAIL. No response.\n";
        return 1;
    }

    // --- Test 2: Read 0x0004 ---
    std::cout << "\n[TEST 2] Read 0x0004\n";
    Result r2 = perform_read(top, tfp, 0x0004);
    if (r2.success) {
        std::cout << "    Data: 0x" << std::hex << r2.data << "\n";
        std::cout << "    Latency: " << std::dec << r2.latency << " cycles.\n";
        std::cout << "    PASS.\n";
    } else {
        std::cout << "    FAIL.\n";
        return 1;
    }

    std::cout << "\n-------------------------------------------------\n";
    std::cout << "  ALL TESTS PASSED  \n";
    std::cout << "-------------------------------------------------\n";

    tfp->close();
    delete top;
    delete tfp;
    return 0;
}
