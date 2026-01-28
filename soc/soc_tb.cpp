#include "Vsoc_harness.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <queue>

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

// UART RX deserializer state
class UartRx {
public:
    int bit_counter = 0;
    int sample_counter = 0;
    uint8_t shift_reg = 0;
    bool in_frame = false;
    int baud_divider = 651; // Matches uart.sv hardcoded value
    
    void tick(int tx_pin) {
        if (!in_frame) {
            // Look for start bit (falling edge)
            if (tx_pin == 0) {
                in_frame = true;
                bit_counter = 0;
                sample_counter = baud_divider / 2; // Sample in middle
                shift_reg = 0;
            }
        } else {
            sample_counter--;
            if (sample_counter == 0) {
                sample_counter = baud_divider;
                
                if (bit_counter < 8) {
                    // Data bits (LSB first)
                    shift_reg = (shift_reg >> 1) | ((tx_pin ? 1 : 0) << 7);
                    bit_counter++;
                } else {
                    // Stop bit - output character
                    if (tx_pin == 1) {
                        char c = (char)shift_reg;
                        std::cout << c << std::flush;
                    }
                    in_frame = false;
                }
            }
        }
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vsoc_harness* top = new Vsoc_harness;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    
    // Enable tracing
    top->trace(tfp, 99);
    tfp->open("soc_tb.vcd");

    UartRx uart_rx;

    top->clk_i = 0;
    top->rst_ni = 0;
    top->uart_rx_i = 1;

    // Reset
    for (int i = 0; i < 20; i++) {
        top->rst_ni = 0;
        top->clk_i = !top->clk_i;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_ni = 1;

    int cycles = 0;
    int max_cycles = 5000000; // Run for 5M cycles (100ms at 50MHz)

    while (!Verilated::gotFinish() && cycles < max_cycles) {
        top->clk_i = !top->clk_i;
        top->eval();
        
        // Capture UART TX output on rising clock edge
        if (top->clk_i) {
            uart_rx.tick(top->uart_tx_o);
            
            static int last_tx = -1;
            if (last_tx != -1 && last_tx != top->uart_tx_o) {
                // std::cout << "[TB] UART TX toggled: " << (int)top->uart_tx_o << " at " << main_time << std::endl;
            }
            last_tx = top->uart_tx_o;

            cycles++;
        }
        
        tfp->dump(main_time++);
    }

    std::cout << "\n\n=== Simulation ended after " << cycles << " cycles ===" << std::endl;

    tfp->close();
    delete top;
    delete tfp;
    return 0;
}
