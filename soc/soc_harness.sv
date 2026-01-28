`timescale 1ns/1ps

module soc_harness (
    input logic clk_i,
    input logic rst_ni,
    output logic uart_tx_o,
    input logic uart_rx_i
);

    // SPI Flash signals (to sim_flash)
    logic spi_flash_cs_n;
    logic spi_flash_sck;
    logic spi_flash_mosi;
    logic spi_flash_miso;

    // Cache AXI signals (unused in this harness, but needed for instantiation)
    logic [3:0]     m_axi_awid;
    logic [26:0]    m_axi_awaddr;
    logic [7:0]     m_axi_awlen;
    logic [2:0]     m_axi_awsize;
    logic [1:0]     m_axi_awburst;
    logic           m_axi_awlock;
    logic [3:0]     m_axi_awcache;
    logic [2:0]     m_axi_awprot;
    logic           m_axi_awvalid;
    logic           m_axi_awready;
    
    logic [31:0]    m_axi_wdata;
    logic [3:0]     m_axi_wstrb;
    logic           m_axi_wlast;
    logic           m_axi_wvalid;
    logic           m_axi_wready;

    logic [3:0]     m_axi_bid;
    logic [1:0]     m_axi_bresp;
    logic           m_axi_bvalid;
    logic           m_axi_bready;

    logic [3:0]     m_axi_arid;
    logic [26:0]    m_axi_araddr;
    logic [7:0]     m_axi_arlen;
    logic [2:0]     m_axi_arsize;
    logic [1:0]     m_axi_arburst;
    logic           m_axi_arlock;
    logic [3:0]     m_axi_arcache;
    logic [2:0]     m_axi_arprot;
    logic           m_axi_arvalid;
    logic           m_axi_arready;

    logic [3:0]     m_axi_rid;
    logic [31:0]    m_axi_rdata;
    logic [1:0]     m_axi_rresp;
    logic           m_axi_rlast;
    logic           m_axi_rvalid;
    logic           m_axi_rready;

    axi_ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(27),
        .ID_WIDTH(4)
    ) ram_inst (
        .clk            (clk_i),
        .rst            (!rst_ni),
        
        .s_axi_awid     (m_axi_awid),
        .s_axi_awaddr   (m_axi_awaddr),
        .s_axi_awlen    (m_axi_awlen),
        .s_axi_awsize   (m_axi_awsize),
        .s_axi_awburst  (m_axi_awburst),
        .s_axi_awlock   (m_axi_awlock),
        .s_axi_awcache  (m_axi_awcache),
        .s_axi_awprot   (m_axi_awprot),
        .s_axi_awvalid  (m_axi_awvalid),
        .s_axi_awready  (m_axi_awready),
        
        .s_axi_wdata    (m_axi_wdata),
        .s_axi_wstrb    (m_axi_wstrb),
        .s_axi_wlast    (m_axi_wlast),
        .s_axi_wvalid   (m_axi_wvalid),
        .s_axi_wready   (m_axi_wready),
        
        .s_axi_bid      (m_axi_bid),
        .s_axi_bresp    (m_axi_bresp),
        .s_axi_bvalid   (m_axi_bvalid),
        .s_axi_bready   (m_axi_bready),
        
        .s_axi_arid     (m_axi_arid),
        .s_axi_araddr   (m_axi_araddr),
        .s_axi_arlen    (m_axi_arlen),
        .s_axi_arsize   (m_axi_arsize),
        .s_axi_arburst  (m_axi_arburst),
        .s_axi_arlock   (m_axi_arlock),
        .s_axi_arcache  (m_axi_arcache),
        .s_axi_arprot   (m_axi_arprot),
        .s_axi_arvalid  (m_axi_arvalid),
        .s_axi_arready  (m_axi_arready),
        
        .s_axi_rid      (m_axi_rid),
        .s_axi_rdata    (m_axi_rdata),
        .s_axi_rresp    (m_axi_rresp),
        .s_axi_rlast    (m_axi_rlast),
        .s_axi_rvalid   (m_axi_rvalid),
        .s_axi_rready   (m_axi_rready)
    );

    soc dut (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        // UART
        .uart_tx_o          (uart_tx_o),
        .uart_rx_i          (uart_rx_i),

        // SPI Flash
        .spi_flash_cs_n_o   (spi_flash_cs_n),
        .spi_flash_sck_o    (spi_flash_sck),
        .spi_flash_mosi_o   (spi_flash_mosi),
        .spi_flash_miso_i   (spi_flash_miso),

        // Cache AXI Interface
        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awlock   (m_axi_awlock),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),

        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),

        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),

        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // Flash Model Wiring
    wire io0, io1, io2, io3;

    assign io0 = spi_flash_mosi;
    assign spi_flash_miso = io1;
    assign io2 = 1'b1;
    assign io3 = 1'b1;

    sim_flash flash_model (
        .csb(spi_flash_cs_n),
        .clk(spi_flash_sck),
        .io0(io0),
        .io1(io1),
        .io2(io2),
        .io3(io3)
    );

endmodule
