`timescale 1ns / 1ps

module cache_tb #(
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 27,
    // Width of wstrb (width of data bus in words)
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    // Width of ID signal
    parameter ID_WIDTH = 8
)(
    input  logic    clk_i,
    input  logic    rst_ni,

    // Bus interface
    input  logic           req_valid_i,
    input  logic [31:0]    req_value_i,
    input  logic [31:0]    req_addr_i,
    input  logic [3:0]     req_wstrb_i,
    output logic           req_ready_o,
    
    output logic           resp_valid_o,
    output logic [31:0]    resp_value_o
);

    logic [ID_WIDTH-1:0]    axi_awid;
    logic [ADDR_WIDTH-1:0]  axi_awaddr;
    logic [7:0]             axi_awlen;
    logic [2:0]             axi_awsize;
    logic [1:0]             axi_awburst;
    logic                   axi_awlock;
    logic [3:0]             axi_awcache;
    logic [2:0]             axi_awprot;
    logic                   axi_awvalid;
    logic                   axi_awready;
    logic [DATA_WIDTH-1:0]  axi_wdata;
    logic [STRB_WIDTH-1:0]  axi_wstrb;
    logic                   axi_wlast;
    logic                   axi_wvalid;
    logic                   axi_wready;
    logic [ID_WIDTH-1:0]    axi_bid;
    logic [1:0]             axi_bresp;
    logic                   axi_bvalid;
    logic                   axi_bready;
    logic [ID_WIDTH-1:0]    axi_arid;
    logic [ADDR_WIDTH-1:0]  axi_araddr;
    logic [7:0]             axi_arlen;
    logic [2:0]             axi_arsize;
    logic [1:0]             axi_arburst;
    logic                   axi_arlock;
    logic [3:0]             axi_arcache;
    logic [2:0]             axi_arprot;
    logic                   axi_arvalid;
    logic                   axi_arready;
    logic [ID_WIDTH-1:0]    axi_rid;
    logic [DATA_WIDTH-1:0]  axi_rdata;
    logic [1:0]             axi_rresp;
    logic                   axi_rlast;
    logic                   axi_rvalid;
    logic                   axi_rready;

    axi_ram mig(
        .clk(clk_i),
        .rst(!rst_ni),

        .s_axi_awid(axi_awid),
        .s_axi_awaddr(axi_awaddr),
        .s_axi_awlen(axi_awlen),
        .s_axi_awsize(axi_awsize),
        .s_axi_awburst(axi_awburst),
        .s_axi_awlock(axi_awlock),
        .s_axi_awcache(axi_awcache),
        .s_axi_awprot(axi_awprot),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),
        .s_axi_wdata(axi_wdata),
        .s_axi_wstrb(axi_wstrb),
        .s_axi_wlast(axi_wlast),
        .s_axi_wvalid(axi_wvalid),
        .s_axi_wready(axi_wready),
        .s_axi_bid(axi_bid),
        .s_axi_bresp(axi_bresp),
        .s_axi_bvalid(axi_bvalid),
        .s_axi_bready(axi_bready),
        .s_axi_arid(axi_arid),
        .s_axi_araddr(axi_araddr),
        .s_axi_arlen(axi_arlen),
        .s_axi_arsize(axi_arsize),
        .s_axi_arburst(axi_arburst),
        .s_axi_arlock(axi_arlock),
        .s_axi_arcache(axi_arcache),
        .s_axi_arprot(axi_arprot),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),
        .s_axi_rid(axi_rid),
        .s_axi_rdata(axi_rdata),
        .s_axi_rresp(axi_rresp),
        .s_axi_rlast(axi_rlast),
        .s_axi_rvalid(axi_rvalid),
        .s_axi_rready(axi_rready)
    );

    cache dut(
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_valid_i(req_valid_i),
        .req_value_i(req_value_i),
        .req_addr_i(req_addr_i),
        .req_wstrb_i(req_wstrb_i),
        .req_ready_o(req_ready_o),
    
        .resp_valid_o(resp_valid_o),
        .resp_value_o(resp_value_o),

        .m_axi_awid(axi_awid),
        .m_axi_awaddr(axi_awaddr),
        .m_axi_awlen(axi_awlen),
        .m_axi_awsize(axi_awsize),
        .m_axi_awburst(axi_awburst),
        .m_axi_awlock(axi_awlock),
        .m_axi_awcache(axi_awcache),
        .m_axi_awprot(axi_awprot),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata),
        .m_axi_wstrb(axi_wstrb),
        .m_axi_wlast(axi_wlast),
        .m_axi_wvalid(axi_wvalid),
        .m_axi_wready(axi_wready),
        .m_axi_bid(axi_bid),
        .m_axi_bresp(axi_bresp),
        .m_axi_bvalid(axi_bvalid),
        .m_axi_bready(axi_bready),
        .m_axi_arid(axi_arid),
        .m_axi_araddr(axi_araddr),
        .m_axi_arlen(axi_arlen),
        .m_axi_arsize(axi_arsize),
        .m_axi_arburst(axi_arburst),
        .m_axi_arlock(axi_arlock),
        .m_axi_arcache(axi_arcache),
        .m_axi_arprot(axi_arprot),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arready),
        .m_axi_rid(axi_rid),
        .m_axi_rdata(axi_rdata),
        .m_axi_rresp(axi_rresp),
        .m_axi_rlast(axi_rlast),
        .m_axi_rvalid(axi_rvalid),
        .m_axi_rready(axi_rready)
    );

endmodule
