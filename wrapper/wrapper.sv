`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/29/2025 11:12:44 PM
// Design Name: 
// Module Name: wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module wrapper #(
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 27,
    // Width of wstrb (width of data bus in words)
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    // Width of ID signal
    parameter ID_WIDTH = 4
)(
    input  logic CLK100MHZ,
    input  logic rst_ni,
    
    output logic uart_tx_o,
    input  logic uart_rx_i,

    output logic spi_flash_cs_n_o,
    output logic spi_flash_sck_o,
    output logic spi_flash_mosi_o,
    input  logic spi_flash_miso_i,
    
    output  logic   SD_RESET,
    output  logic   SD_SCK,
    output  logic   SD_DI,
    output  logic   SD_CS,
    input   logic   SD_DO,

    output wire [12:0] ddr2_addr,
    output wire [2:0]  ddr2_ba,
    output wire        ddr2_cas_n,
    output wire [0:0]  ddr2_ck_n,
    output wire [0:0]  ddr2_ck_p,
    output wire [0:0]  ddr2_cke,
    output wire        ddr2_ras_n,
    output wire        ddr2_we_n,
    
    // INOUTS - Critical for bidirectional data
    inout  wire [15:0] ddr2_dq,
    inout  wire [1:0]  ddr2_dqs_n,
    inout  wire [1:0]  ddr2_dqs_p,
    
    output wire [0:0]  ddr2_cs_n,
    output wire [1:0]  ddr2_dm,
    output wire [0:0]  ddr2_odt,
    
    output logic       LED0,
    output logic       LED1,
    output logic       LED2,
    output logic       LED3,
    output logic       LED4,
    output logic       LED5,
    output logic       LED6,
    output logic       LED7,
    output logic       LED8,
    output logic       LED9,
    output logic       LED10,
    output logic       LED11,
    output logic       LED12,
    output logic       LED13,
    output logic       LED14,
    output logic       LED15    
    );
    
    assign SD_RESET = 1'b0;

    logic CLK200MHZ;
    logic locked;
    logic init_calib_complete;
    
    logic [31:0] pc;
    logic [2:0] mmu_state;
    
    assign LED0 = pc[2];
    assign LED1 = pc[3];
    assign LED2 = pc[4];
    assign LED3 = pc[5];
    assign LED4 = pc[6];
    assign LED5 = pc[7];
    assign LED6 = pc[8];
    assign LED7 = pc[9];
    assign LED8 = pc[10];
    assign LED9 = pc[11];
    assign LED10 = pc[12];
    assign LED11 = pc[13];
    assign LED12 = pc[14];
    assign LED13 = mmu_state[0];
    assign LED14 = mmu_state[1];
    assign LED15 = mmu_state[2];

    

    clk_wiz_0 instance_name
    (
        // Clock out ports
        .clk_out1(CLK200MHZ),     // output clk_out1
        // Status and control signals
        .reset(!rst_ni), // input reset
        .locked(locked),       // output locked
    // Clock in ports
        .clk_in1(CLK100MHZ)      // input clk_in1
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


  mig_7series_0 u_mig_7series_0 (
    // Memory interface ports
    .ddr2_addr                      (ddr2_addr),  // output [12:0]                       ddr2_addr
    .ddr2_ba                        (ddr2_ba),  // output [2:0]                      ddr2_ba
    .ddr2_cas_n                     (ddr2_cas_n),  // output                                       ddr2_cas_n
    .ddr2_ck_n                      (ddr2_ck_n),  // output [0:0]                        ddr2_ck_n
    .ddr2_ck_p                      (ddr2_ck_p),  // output [0:0]                        ddr2_ck_p
    .ddr2_cke                       (ddr2_cke),  // output [0:0]                       ddr2_cke
    .ddr2_ras_n                     (ddr2_ras_n),  // output                                       ddr2_ras_n
    .ddr2_we_n                      (ddr2_we_n),  // output                                       ddr2_we_n
    .ddr2_dq                        (ddr2_dq),  // inout [15:0]                         ddr2_dq
    .ddr2_dqs_n                     (ddr2_dqs_n),  // inout [1:0]                        ddr2_dqs_n
    .ddr2_dqs_p                     (ddr2_dqs_p),  // inout [1:0]                        ddr2_dqs_p
    .init_calib_complete            (init_calib_complete),  // output                                       init_calib_complete
      
	.ddr2_cs_n                      (ddr2_cs_n),  // output [0:0]           ddr2_cs_n
    .ddr2_dm                        (ddr2_dm),  // output [1:0]                        ddr2_dm
    .ddr2_odt                       (ddr2_odt),  // output [0:0]                       ddr2_odt
    // Application interface ports
    .ui_clk                         (ui_clk),  // output                                       ui_clk
    .ui_clk_sync_rst                (ui_clk_sync_rst),  // output                                       ui_clk_sync_rst
    .mmcm_locked                    (mmcm_locked),  // 
    .aresetn                        (1'b1),  // 
    .app_sr_req                     (1'b0),  // input                                        app_sr_req
    .app_ref_req                    (1'b0),  // input                                        app_ref_req
    .app_zq_req                     (1'b0),  // input                                        app_zq_req
    .app_sr_active                  (app_sr_active),  // output                                       app_sr_active
    .app_ref_ack                    (app_ref_ack),  // output                                       app_ref_ack
    .app_zq_ack                     (app_zq_ack),  // output                                       app_zq_ack
    // Slave Interface Write Address Ports
    .s_axi_awid                     (axi_awid),  // input  [3:0]                s_axi_awid
    .s_axi_awaddr                   (axi_awaddr),  // input  [26:0]              s_axi_awaddr
    .s_axi_awlen                    (axi_awlen),  // input  [7:0]                                 s_axi_awlen
    .s_axi_awsize                   (axi_awsize),  // input  [2:0]                                 s_axi_awsize
    .s_axi_awburst                  (axi_awburst),  // input  [1:0]                                 s_axi_awburst
    .s_axi_awlock                   (axi_awlock),  // input  [0:0]                                 s_axi_awlock
    .s_axi_awcache                  (axi_awcache),  // input  [3:0]                                 s_axi_awcache
    .s_axi_awprot                   (axi_awprot),  // input  [2:0]                                 s_axi_awprot
    .s_axi_awqos                    (4'b0000),  // input  [3:0]                                 s_axi_awqos
    .s_axi_awvalid                  (axi_awvalid),  // input                                        s_axi_awvalid
    .s_axi_awready                  (axi_awready),  // output                                       s_axi_awready
    // Slave Interface Write Data Ports
    .s_axi_wdata                    (axi_wdata),  // input  [31:0]              s_axi_wdata
    .s_axi_wstrb                    (axi_wstrb),  // input  [3:0]            s_axi_wstrb
    .s_axi_wlast                    (axi_wlast),  // input                                        s_axi_wlast
    .s_axi_wvalid                   (axi_wvalid),  // input                                        s_axi_wvalid
    .s_axi_wready                   (axi_wready),  // output                                       s_axi_wready
    // Slave Interface Write Response Ports
    .s_axi_bid                      (axi_bid),  // output [3:0]                s_axi_bid
    .s_axi_bresp                    (axi_bresp),  // output [1:0]                                 s_axi_bresp
    .s_axi_bvalid                   (axi_bvalid),  // output                                       s_axi_bvalid
    .s_axi_bready                   (axi_bready),  // input                                        s_axi_bready
    // Slave Interface Read Address Ports
    .s_axi_arid                     (axi_arid),  // input  [3:0]                s_axi_arid
    .s_axi_araddr                   (axi_araddr),  // input  [26:0]              s_axi_araddr
    .s_axi_arlen                    (axi_arlen),  // input  [7:0]                                 s_axi_arlen
    .s_axi_arsize                   (axi_arsize),  // input  [2:0]                                 s_axi_arsize
    .s_axi_arburst                  (axi_arburst),  // input  [1:0]                                 s_axi_arburst
    .s_axi_arlock                   (axi_arlock),  // input  [0:0]                                 s_axi_arlock
    .s_axi_arcache                  (axi_arcache),  // input  [3:0]                                 s_axi_arcache
    .s_axi_arprot                   (axi_arprot),  // input  [2:0]                                 s_axi_arprot
    .s_axi_arqos                    (4'b0000),  // input  [3:0]                                 s_axi_arqos
    .s_axi_arvalid                  (axi_arvalid),  // input                                        s_axi_arvalid
    .s_axi_arready                  (axi_arready),  // output                                       s_axi_arready
    // Slave Interface Read Data Ports
    .s_axi_rid                      (axi_rid),  // output [3:0]                s_axi_rid
    .s_axi_rdata                    (axi_rdata),  // output [31:0]              s_axi_rdata
    .s_axi_rresp                    (axi_rresp),  // output [1:0]                                 s_axi_rresp
    .s_axi_rlast                    (axi_rlast),  // output                                       s_axi_rlast
    .s_axi_rvalid                   (axi_rvalid),  // output                                       s_axi_rvalid
    .s_axi_rready                   (axi_rready),  // input                                        s_axi_rready
    // System Clock Ports
    .sys_clk_i                       (CLK200MHZ),  // input                                        sys_clk_i
    .sys_rst                        (rst_ni && locked) // input  sys_rst
    );

    soc soc_0(
        .clk_i(ui_clk),
        .rst_ni(init_calib_complete && rst_ni),
        .uart_tx_o(uart_tx_o),
        .uart_rx_i(uart_rx_i),

        .spi_flash_cs_n_o(spi_flash_cs_n_o),
        .spi_flash_sck_o(spi_flash_sck_o),
        .spi_flash_mosi_o(spi_flash_mosi_o),
        .spi_flash_miso_i(spi_flash_miso_i),

        .spi_sd_cs_n_o(SD_CS),
        .spi_sd_sck_o(SD_SCK),
        .spi_sd_mosi_o(SD_DI),
        .spi_sd_miso_i(SD_DO),
        
        .pc_o(pc),
        .state_o(mmu_state),

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
