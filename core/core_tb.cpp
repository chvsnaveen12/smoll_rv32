
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vcore_fsm.h"
#include <iostream>
#include <iomanip>
#include <map>

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

#include <fstream>
#include <string>
#include <vector>

// ... (includes remain the same)

// Latency settings
int REQ_READY_LATENCY = 0;
int RESP_VALID_LATENCY = 1;
int MAX_CYCLES = 10000000; // Default max cycles

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    if (argc < 4) {
        std::cerr << "Usage: " << argv[0] << " BIN_FILE DUMP_START DUMP_END" << std::endl;
        return 1;
    }

    std::string bin_file = argv[1];
    uint32_t dump_start = std::stoul(argv[2], nullptr, 16);
    uint32_t dump_end = std::stoul(argv[3], nullptr, 16);

    Vcore_fsm* top = new Vcore_fsm;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    
    top->trace(tfp, 99);
    tfp->open("core_tb_cpp.vcd");

    // Memory Array
    std::map<uint32_t, uint32_t> memory;
    
    // Load Binary
    std::ifstream file(bin_file, std::ios::binary | std::ios::ate);
    if (!file) {
        std::cerr << "Error: Could not open file " << bin_file << std::endl;
        return 1;
    }
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<char> buffer(size);
    if (file.read(buffer.data(), size)) {
        for (size_t i = 0; i < size; i++) {
            uint32_t addr = 0x80000000 + i;
            uint32_t word_addr = addr & ~3;
            uint32_t byte_offset = addr & 3;
            
            // Read existing word or 0
            uint32_t current_word = memory[word_addr];
            
            // Modify the specific byte
            uint32_t byte_val = (uint8_t)buffer[i];
            uint32_t mask = ~(0xFF << (byte_offset * 8));
            memory[word_addr] = (current_word & mask) | (byte_val << (byte_offset * 8));
        }
    }
    
    // Initialize signals
    top->clk_i = 0;
    top->rst_ni = 0;
    top->req_ready_i = 0;
    top->resp_valid_i = 0;
    top->resp_value_i = 0;
    top->m_ext_irq_i = 0;
    top->m_timer_irq_i = 0;
    top->m_soft_irq_i = 0;

    // Reset
    for (int i = 0; i < 10; i++) {
        top->rst_ni = 0;
        top->clk_i = !top->clk_i;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_ni = 1;

    // Simulation loop
    bool req_pending = false;
    uint32_t last_req_addr = 0;
    uint32_t last_req_wstrb = 0;
    uint32_t last_req_wdata = 0;
    int cycles = 0;

    int ready_cnt = REQ_READY_LATENCY;
    int valid_cnt = 0;
    bool processing_req = false;

    while (!Verilated::gotFinish() && cycles < MAX_CYCLES) {
        top->clk_i = !top->clk_i;
        top->eval();
        
        if (top->clk_i) { // Rising edge
            // Handle Ready Signal
            if (!processing_req) {
                if (ready_cnt > 0) {
                    top->req_ready_i = 0;
                    ready_cnt--;
                } else {
                    top->req_ready_i = 1;
                }
            } else {
                top->req_ready_i = 0; // Busy processing
            }

            // Capture Request
            if (top->req_valid_o && top->req_ready_i) {
                processing_req = true;
                last_req_addr = top->req_addr_o;
                last_req_wstrb = top->req_wstrb_o;
                last_req_wdata = top->req_value_o;
                valid_cnt = RESP_VALID_LATENCY;
                ready_cnt = REQ_READY_LATENCY; 
                
                // Debug Print
                // std::cout << "Cycle: " << cycles << " Req Addr: " << std::hex << last_req_addr 
                //           << " WSTRB: " << last_req_wstrb << " WData: " << last_req_wdata << std::endl;
            }
            
            // Handle Response Valid Pulse
            if (processing_req) {
                 if (valid_cnt > 0) {
                     valid_cnt--;
                     top->resp_valid_i = 0;
                 } else {
                     top->resp_valid_i = 1;
                     
                     if (last_req_wstrb != 0) { // MMU_STORE
                        if(last_req_addr == 0x10000008){
                            putc((uint8_t)last_req_wdata, stdout);
                        } else {
                        if(last_req_wstrb & 1)
                            ((uint8_t*)&memory[last_req_addr])[0] = (uint8_t)last_req_wdata;
                        if(last_req_wstrb & 2)
                            ((uint8_t*)&memory[last_req_addr])[1] = (uint8_t)(last_req_wdata >> 8);
                        if(last_req_wstrb & 4)
                            ((uint8_t*)&memory[last_req_addr])[2] = (uint8_t)(last_req_wdata >> 16);
                        if(last_req_wstrb & 8)
                            ((uint8_t*)&memory[last_req_addr])[3] = (uint8_t)(last_req_wdata >> 24);
                         top->resp_value_i = 0;
                        }
                     } else { // FETCH or LOAD
                        if(last_req_addr == 0x1000000c){
                            top->resp_value_i = 0;
                        } else {
                         if (memory.find(last_req_addr) != memory.end()) {
                             top->resp_value_i = memory[last_req_addr];
                         } else {
                             top->resp_value_i = 0; // Default 0
                         }
                        }
                     }
                     processing_req = false;
                 }
            } else {
                top->resp_valid_i = 0;
            }

        }

        tfp->dump(main_time++);
        if (top->clk_i) cycles++;
    }

    // Dump Memory
    for (uint32_t addr = dump_start; addr < dump_end; addr += 4) {
        uint32_t val = 0;
        if (memory.find(addr) != memory.end()) {
            val = memory[addr];
        }
        std::cout << std::hex << std::setw(8) << std::setfill('0') << val << std::endl;
    }

    top->final();
    tfp->close();
    delete top;
    delete tfp;
    return 0;
}