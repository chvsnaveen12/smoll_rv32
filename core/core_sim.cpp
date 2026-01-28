
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vcore_fsm.h"
#include <iostream>
#include <iomanip>
#include <map>
#include <fstream>
#include <string>
#include <vector>

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

// Latency settings
int REQ_READY_LATENCY = 0;
int RESP_VALID_LATENCY = 1;
int MAX_CYCLES = 500000; // Increased for booting

void load_binary(std::map<uint32_t, uint32_t>& memory, const std::string& filename, uint32_t base_addr) {
    std::ifstream file(filename, std::ios::binary | std::ios::ate);
    if (!file) {
        std::cerr << "Error: Could not open file " << filename << std::endl;
        exit(1);
    }
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<char> buffer(size);
    if (file.read(buffer.data(), size)) {
        for (size_t i = 0; i < size; i++) {
            uint32_t addr = base_addr + i;
            uint32_t word_addr = addr & ~3;
            uint32_t byte_offset = addr & 3;
            
            uint32_t current_word = memory[word_addr];
            uint32_t byte_val = (uint8_t)buffer[i];
            uint32_t mask = ~(0xFF << (byte_offset * 8));
            memory[word_addr] = (current_word & mask) | (byte_val << (byte_offset * 8));
        }
    }
    std::cout << "Loaded " << filename << " (" << size << " bytes) at 0x" << std::hex << base_addr << std::dec << std::endl;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " OPENSBI_BIN DTB_FILE" << std::endl;
        return 1;
    }

    std::string sbi_file = argv[1];
    std::string dtb_file = argv[2];

    Vcore_fsm* top = new Vcore_fsm;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    
    top->trace(tfp, 99);
    tfp->open("core_sim.vcd");

    // Memory Array
    std::map<uint32_t, uint32_t> memory;
    
    // Load Binaries
    load_binary(memory, sbi_file, 0x80000000);
    load_binary(memory, dtb_file, 0x86000000);

    // Bootrom at 0x40000000
    uint32_t boot_rom[] = {
        0x00000297,                 /* 1:  auipc  t0, %pcrel_hi(fw_dyn) */
        0x02828613,                 /*     addi   a2, t0, %pcrel_lo(1b) */
        0xf1402573,                 /*     csrr   a0, mhartid  */
        0x0202a583,                 /*     lw     a1, 32(t0) */
        0x0182a283,                 /*     lw     t0, 24(t0) */
        0x00028067,                 /*     jr     t0 */
        0x80000000,                 /* start: .dword (RAM_BASE) */
        0x00000000,
        0x86000000,                 /* fdt_laddr: .dword (FDT_ADDR) */
        0x00000000,
                                    /* fw_dyn: */
        0x4942534f,                 /* OSBI */
        0x00000002,                 /* Version */
        0x80400000,                 /* Next stage addr (LINUX_ADDR) */
        0x00000001,                 /* Next stage mode (Supervisor) */
        0x00000000,                 /* OpenSBI options */
        0x00000000                  /* Boot Hart */
    };
    for (int i = 0; i < sizeof(boot_rom)/4; i++) {
        memory[0x40000000 + i*4] = boot_rom[i];
    }
    std::cout << "Initialized Bootrom at 0x40000000" << std::endl;

    // Initialize signals
    top->clk_i = 0;
    top->rst_ni = 0;
    top->req_ready_i = 0;
    top->resp_valid_i = 0;
    top->resp_value_i = 0;
    top->m_ext_irq_i = 0;
    top->m_timer_irq_i = 0;
    top->m_soft_irq_i = 0;
    top->s_ext_irq_i = 0;

    // Reset
    for (int i = 0; i < 10; i++) {
        top->rst_ni = 0;
        top->clk_i = !top->clk_i;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_ni = 1;

    // Simulation loop
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
            }
            
            // Handle Response Valid Pulse
            if (processing_req) {
                 if (valid_cnt > 0) {
                     valid_cnt--;
                     top->resp_valid_i = 0;
                 } else {
                     top->resp_valid_i = 1;
                     
                     if (last_req_wstrb != 0) { // STORE
                        if(last_req_addr == 0x10000008){
                            putchar((uint8_t)last_req_wdata);
                            fflush(stdout);
                        } else {
                            if(last_req_wstrb & 1)
                                ((uint8_t*)&memory[last_req_addr])[0] = (uint8_t)last_req_wdata;
                            if(last_req_wstrb & 2)
                                ((uint8_t*)&memory[last_req_addr])[1] = (uint8_t)(last_req_wdata >> 8);
                            if(last_req_wstrb & 4)
                                ((uint8_t*)&memory[last_req_addr])[2] = (uint8_t)(last_req_wdata >> 16);
                            if(last_req_wstrb & 8)
                                ((uint8_t*)&memory[last_req_addr])[3] = (uint8_t)(last_req_wdata >> 24);
                        }
                        top->resp_value_i = 0;
                     } else { // FETCH or LOAD
                        if(last_req_addr == 0x10000000){ // RX Data
                            top->resp_value_i = 0;
                        } else if(last_req_addr == 0x10000004){ // RX IRQ
                            top->resp_value_i = 0;
                        } else if(last_req_addr == 0x100000c8){ // TX Data read back
                            top->resp_value_i = 0;
                        } else if(last_req_addr == 0x1000000c){ // TX Busy
                            top->resp_value_i = 0;
                        } else {
                            if (memory.find(last_req_addr) != memory.end()) {
                                top->resp_value_i = memory[last_req_addr];
                            } else {
                                top->resp_value_i = 0;
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

    top->final();
    tfp->close();
    delete top;
    delete tfp;
    return 0;
}
