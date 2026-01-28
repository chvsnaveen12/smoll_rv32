`timescale 1ns/1ps

module spi_harness #()(
    input logic clk_i,
    input logic rst_ni,

    input logic req_valid_i,
    input logic [31:0] req_addr_i,
    input logic [31:0] req_value_i,
    input logic [3:0] req_wstrb_i,
    output logic req_ready_o,
    output logic resp_valid_o,
    output logic [31:0] resp_value_o
);
    logic cs_n;
    logic sck;
    logic mosi;
    logic miso;

    wire io0, io1;

    // DUT
    flash_controller dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_valid_i(req_valid_i),
        .req_addr_i(req_addr_i),
        .req_value_i(req_value_i),
        .req_wstrb_i(|req_wstrb_i),
        .req_ready_o(req_ready_o),
        .resp_valid_o(resp_valid_o),
        .resp_value_o(resp_value_o),
        .cs_no(cs_n),
        .sck_o(sck),
        .mosi_o(mosi),
        .miso_i(miso)
    );

    assign io0 = mosi;
    assign miso = io1;
    
    // Pullups for unused pins
    wire io2, io3;
    assign io2 = 1'b1;
    assign io3 = 1'b1;

    sim_flash flash_model (
        .csb(cs_n),
        .clk(sck),
        .io0(io0),
        .io1(io1),
        .io2(io2),
        .io3(io3)
    );
endmodule
