#include <iostream>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vclint.h"

vluint64_t main_time = 0;

void tick(Vclint *top, VerilatedVcdC *tfp){
    top->clk_i = 0;
    top->eval();
    if(tfp) tfp->dump(main_time++);

    top->clk_i = 1;
    top->eval();
    if(tfp) tfp->dump(main_time++);
}

u_int32_t read(Vclint *top, VerilatedVcdC *tfp, u_int32_t addr){
    bool ready;
    top->req_valid_i = 1;
    top->req_addr_i = addr;
    top->req_wstrb_i = 0x0;
    vluint64_t timeout = 1000;
    do{
        ready = top->req_ready_o;
        tick(top, tfp);
        if(!timeout--) break;
    }while(!ready);
    top->req_valid_i = 0;
    tick(top, tfp);

    timeout = 1000;
    while(!top->resp_valid_o){
        tick(top, tfp);
        if(!timeout--) break;
    }
    u_int32_t ret_val = top->resp_value_o;
    tick(top, tfp);
    return ret_val;
}

void write(Vclint *top, VerilatedVcdC *tfp, u_int32_t addr, u_int32_t value){
    bool ready;
    top->req_valid_i = 1;
    top->req_value_i = value;
    top->req_addr_i  = addr;
    top->req_wstrb_i = 0xf;
    vluint64_t timeout = 1000;
    do{
        ready = top->req_ready_o;
        tick(top, tfp);
        if(!timeout--) break;
        printf("Timeout: %ld\n", timeout);
    }while(!ready);
    top->req_valid_i = 0;
    top->req_value_i = 0;
    top->req_addr_i  = 0;
    top->req_wstrb_i = 0;
    tick(top, tfp);
    
    // Wait for response valid (though write response value might not matter, handshake does)
    timeout = 1000;
    while(!top->resp_valid_o){
        tick(top, tfp);
        if(!timeout--) break;
    }
    tick(top, tfp);
}

int main(int argc, char **argv, char **env){
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vclint *dut = new Vclint;
    VerilatedVcdC *tfp = new VerilatedVcdC;

    dut->trace(tfp, 99);
    tfp->open("clint_tb.vcd");

    dut->rst_ni = 0;
    dut->req_valid_i = 0;
    dut->req_value_i = 0;
    dut->req_addr_i = 0;

    printf("Resetting...\n");
    for(int i = 0; i < 20; i++) tick(dut, tfp);
    dut->rst_ni = 1;
    for(int i = 0; i < 5; i++) tick(dut, tfp);

    // Test MSIP
    printf("Testing MSIP...\n");
    write(dut, tfp, 0x0, 1);
    if(dut->msi_o != 1) printf("ERROR: MSI not asserted after writing 1 to MSIP\n");
    else printf("MSI asserted correctly\n");

    write(dut, tfp, 0x0, 0);
    if(dut->msi_o != 0) printf("ERROR: MSI not de-asserted after writing 0 to MSIP\n");
    else printf("MSI de-asserted correctly\n");

    // Test MTIME and MTIMECMP
    printf("Testing Timer Interrupt...\n");
    
    // Read current MTIME
    u_int32_t mtime_l = read(dut, tfp, 0xbff8);
    u_int32_t mtime_h = read(dut, tfp, 0xbffc);
    printf("Current MTIME: 0x%08x%08x\n", mtime_h, mtime_l);

    // Set MTIMECMP to a value slightly in the future
    // Assuming MTIME is small since reset.
    // Let's write MTIMECMP to be current MTIME + 100 ticks (approx)
    // Note: clint.sv has a prescaler MTIME_DIV = 4.
    
    // Write MTIMECMP
    write(dut, tfp, 0x4000, 100); // Low
    write(dut, tfp, 0x4004, 0);   // High

    printf("Waiting for interrupt...\n");
    // Wait enough time for mtime to increment past 100
    // 100 ticks * 4 (prescaler) = 400 cycles roughly
    for(int i = 0; i < 600; i++) tick(dut, tfp);

    if(dut->mti_o != 1) printf("ERROR: MTI not asserted after timeout\n");
    else printf("MTI asserted correctly\n");

    // Clear interrupt by setting MTIMECMP higher
    write(dut, tfp, 0x4004, 1); // High part to 1 -> huge value
    
    // Give it a cycle to update
    tick(dut, tfp);
    tick(dut, tfp);

    if(dut->mti_o != 0) printf("ERROR: MTI not de-asserted after increasing MTIMECMP\n");
    else printf("MTI de-asserted correctly\n");

    printf("Testbench completed.\n");

    tfp->close();
    delete dut;
    delete tfp;
    return 0;
}
