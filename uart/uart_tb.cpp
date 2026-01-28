#include <iostream>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vuart.h"

vluint64_t main_time = 0;

void tick(Vuart *top, VerilatedVcdC *tfp){
    top->clk_i = 0;
    top->rx_i = top->tx_o;
    top->eval();
    if(tfp) tfp->dump(main_time++);

    top->clk_i = 1;
    top->rx_i = top->tx_o;
    top->eval();
    if(tfp) tfp->dump(main_time++);
}

u_int32_t read(Vuart *top, VerilatedVcdC *tfp, u_int32_t addr){
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

void write(Vuart *top, VerilatedVcdC *tfp, u_int32_t addr, u_int32_t value){
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
        printf("TImeout: %ld\n", timeout);
    }while(!ready);
    top->req_valid_i = 0;
    top->req_value_i = 0;
    top->req_addr_i  = 0;
    top->req_wstrb_i = 0;
    tick(top, tfp);
}

int main(int argc, char **argv, char **env){
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vuart *dut = new Vuart;
    VerilatedVcdC *tfp = new VerilatedVcdC;

    dut->trace(tfp, 99);
    tfp->open("uart_tb.vcd");

    dut->rst_ni = 0;
    dut->req_valid_i = 0;
    dut->req_value_i = 0;
    dut->req_addr_i = 0;

    for(int i = 0; i < 20; i++) tick(dut, tfp);
    dut->rst_ni = 1;
    for(int i = 0; i < 5; i++) tick(dut, tfp);

    
    // dut->req_valid_i = 1;
    // dut->req_value_i = 0;
    // dut->req_addr_i  = 0;
    // dut->req_wstrb_i = 0;

    // write(dut, tfp, 0x0, 0x1);
    write(dut, tfp, 0x8, 0xaa);
    write(dut, tfp, 0xc, 0x1);
    // write(dut, tfp, 0x18, 0x4);
    // write(dut, tfp, 0x20, 0x5);
    // write(dut, tfp, 0x28, 0x6);
    // write(dut, tfp, 0x30, 0x7);
    // write(dut, tfp, 0x38, 0x8);
    // write(dut, tfp, 0x3c, 0xffff);
    // write(dut, tfp, 4096, 0x02);
    // for(int i = 16; i < 32; i++)
        // printf("Read at %d: 0x%08x\n",i*4, read(dut, tfp, i*4));
    // for(int i = 0; i < 16; i++)
        // printf("Read at %d: 0x%08x\n",i*4, read(dut, tfp, i*4));
    unsigned int temp = read(dut, tfp, 0x04);
    printf("Read at 0x04: 0x%08x\n", temp);
    while(temp == 0x0){
        temp = read(dut, tfp, 0x04);
        printf("Read at 0x04: 0x%08x\n", temp);
        tick(dut, tfp);
    }
    unsigned int temp2 = read(dut, tfp, 0x0);
    printf("Read at 0x00: 0x%08x\n", temp2);
    temp = read(dut, tfp, 0x04);
    printf("Read at 0x04: 0x%08x\n", temp);

    // printf("Read at 4096: 0x%08x\n", read(dut, tfp, 4096));
    // vluint64_t timeout = 100;
    // while(!dut->req_valid_i || !dut->req_ready_o){
    //     tick(dut, tfp);
    //     if(!timeout--) break;
    // }

    for(int i = 0; i < 200; i++)
        tick(dut, tfp);

    tfp->close();
    delete dut;
    delete tfp;
    return 0;
}