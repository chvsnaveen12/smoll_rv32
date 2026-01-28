module soc #()( 
    input   logic   clk_i,
    input   logic   rst_ni,

    // UART
    output  logic   uart_tx_o,
    input   logic   uart_rx_i,

    // SPI Flash (XIP)
    output  logic   spi_flash_cs_n_o,
    output  logic   spi_flash_sck_o,
    output  logic   spi_flash_mosi_o,
    input   logic   spi_flash_miso_i,

    // SPI SD
    output  logic   spi_sd_cs_n_o,
    output  logic   spi_sd_sck_o,
    output  logic   spi_sd_mosi_o,
    input   logic   spi_sd_miso_i,

    // Cache AXI Interface (optional - for external memory)
    output  logic [3:0]     m_axi_awid,
    output  logic [26:0]    m_axi_awaddr,
    output  logic [7:0]     m_axi_awlen,
    output  logic [2:0]     m_axi_awsize,
    output  logic [1:0]     m_axi_awburst,
    output  logic           m_axi_awlock,
    output  logic [3:0]     m_axi_awcache,
    output  logic [2:0]     m_axi_awprot,
    output  logic           m_axi_awvalid,
    input   logic           m_axi_awready,
    
    output  logic [31:0]    m_axi_wdata,
    output  logic [3:0]     m_axi_wstrb,
    output  logic           m_axi_wlast,
    output  logic           m_axi_wvalid,
    input   logic           m_axi_wready,

    input   logic [3:0]     m_axi_bid,
    input   logic [1:0]     m_axi_bresp,
    input   logic           m_axi_bvalid,
    output  logic           m_axi_bready,

    output  logic [3:0]     m_axi_arid,
    output  logic [26:0]    m_axi_araddr,
    output  logic [7:0]     m_axi_arlen,
    output  logic [2:0]     m_axi_arsize,
    output  logic [1:0]     m_axi_arburst,
    output  logic           m_axi_arlock,
    output  logic [3:0]     m_axi_arcache,
    output  logic [2:0]     m_axi_arprot,
    output  logic           m_axi_arvalid,
    input   logic           m_axi_arready,

    input   logic [3:0]     m_axi_rid,
    input   logic [31:0]    m_axi_rdata,
    input   logic [1:0]     m_axi_rresp,
    input   logic           m_axi_rlast,
    input   logic           m_axi_rvalid,
    output  logic           m_axi_rready
);

    // ---------------------------------------------------------
    // Interrupt Signals
    // ---------------------------------------------------------
    logic m_ext_irq;
    logic m_timer_irq;
    logic m_soft_irq;
    logic s_ext_irq;

    // Collect IRQs from peripherals
    logic uart_rx_irq;

    // Simple IRQ aggregation
    assign m_ext_irq   = uart_rx_irq;
    assign m_timer_irq = 1'b0;  // No timer yet
    assign m_soft_irq  = 1'b0;
    assign s_ext_irq   = 1'b0;

    // ---------------------------------------------------------
    // Core Signals
    // ---------------------------------------------------------
    logic           core_req_valid;
    logic [31:0]    core_req_addr;
    logic [31:0]    core_req_value;
    logic           core_req_is_fetch;
    logic [3:0]     core_req_wstrb;
    logic [31:0]    core_req_satp;
    logic           core_req_mxr;
    logic           core_req_sum;
    logic           core_req_mprv;
    logic [1:0]     core_req_priv;
    logic           core_req_ready;
    
    logic           core_resp_valid;
    logic [31:0]    core_resp_value;
    logic           core_resp_ex_valid;
    logic [31:0]    core_resp_ex_code;

    // Unused MMU signals - directly pass through
    assign core_resp_ex_valid = 1'b0;
    assign core_resp_ex_code  = 32'b0;

    // ---------------------------------------------------------
    // Peripheral Bus Signals
    // ---------------------------------------------------------
    // UART (0x1000_0000)
    logic           uart_req_valid;
    logic           uart_req_ready;
    logic           uart_resp_valid;
    logic [31:0]    uart_resp_value;

    // Cache (0x8000_0000)
    logic           cache_req_valid;
    logic           cache_req_ready;
    logic           cache_resp_valid;
    logic [31:0]    cache_resp_value;

    // XIP Flash Controller (0x9000_0000)
    logic           xip_req_valid;
    logic           xip_req_ready;
    logic           xip_resp_valid;
    logic [31:0]    xip_resp_value;

    // SPI SD (0x9000_0000)
    logic           spi_req_valid;
    logic           spi_req_ready;
    logic           spi_resp_valid;
    logic [31:0]    spi_resp_value;

    // Dummy (catches unmatched addresses)
    logic           dummy_req_valid;
    logic           dummy_req_ready;
    logic           dummy_resp_valid;
    logic [31:0]    dummy_resp_value;

    // ---------------------------------------------------------
    // Memory Map (Using upper 4 bits for address decoding)
    // ---------------------------------------------------------
    localparam BASE_UART  = 4'h1;   // 0x1000_0000
    localparam BASE_SPI   = 4'h2;   // 0x2000_0000
    localparam BASE_XIP   = 4'h4;   // 0x4000_0000
    localparam BASE_CACHE = 4'h8;   // 0x8000_0000

    // Address Decoding
    logic [3:0] req_prefix;
    logic [31:0] trunc_address;
    assign req_prefix = core_req_addr[31:28];
    assign trunc_address = {4'b0000, core_req_addr[27:0]};

    // ---------------------------------------------------------
    // Request Arbiter / Address Decoder
    // ---------------------------------------------------------
    always_comb begin
        // Default: nothing selected
        uart_req_valid   = 1'b0;
        cache_req_valid  = 1'b0;
        xip_req_valid    = 1'b0;
        spi_req_valid    = 1'b0;
        dummy_req_valid  = 1'b0;
        core_req_ready   = 1'b0;

        if (core_req_valid) begin
            case (req_prefix)
                BASE_UART: begin
                    uart_req_valid   = 1'b1;
                    core_req_ready   = uart_req_ready;
                end
                BASE_CACHE: begin
                    cache_req_valid  = 1'b1;
                    core_req_ready   = cache_req_ready;
                end
                BASE_XIP: begin
                    xip_req_valid    = 1'b1;
                    core_req_ready   = xip_req_ready;
                end
                BASE_SPI: begin
                    spi_req_valid    = 1'b1;
                    core_req_ready   = spi_req_ready;
                end 
                default: begin
                    // Dummy catches all unmatched addresses
                    dummy_req_valid  = 1'b1;
                    core_req_ready   = dummy_req_ready;
                end
            endcase
        end
    end

    // ---------------------------------------------------------
    // Response Mux
    // ---------------------------------------------------------
    always_comb begin
        core_resp_valid = 1'b0;
        core_resp_value = 32'b0;

        // Priority encoded mux (only one should be valid at a time)
        if (uart_resp_valid) begin
            core_resp_valid = 1'b1;
            core_resp_value = uart_resp_value;
        end else if (cache_resp_valid) begin
            core_resp_valid = 1'b1;
            core_resp_value = cache_resp_value;
        end else if (xip_resp_valid) begin
            core_resp_valid = 1'b1;
            core_resp_value = xip_resp_value;
        end else if (spi_resp_valid) begin
            core_resp_valid = 1'b1;
            core_resp_value = spi_resp_value;
        end else if (dummy_resp_valid) begin
            core_resp_valid = 1'b1;
            core_resp_value = dummy_resp_value;
        end
    end

    // ---------------------------------------------------------
    // Dummy Responder (Prevents Bus Stalls on Invalid Addresses)
    // ---------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            dummy_req_ready  <= 1'b0;
            dummy_resp_valid <= 1'b0;
            dummy_resp_value <= 32'h0;
        end else begin
            dummy_req_ready  <= 1'b1;
            dummy_resp_valid <= 1'b0;

            if (dummy_req_valid) begin
                dummy_resp_valid <= 1'b1;
                dummy_resp_value <= 32'h0;
            end
        end
    end

    // =========================================================
    // Module Instantiations
    // =========================================================

    // ---------------------------------------------------------
    // CPU Core
    // ---------------------------------------------------------
    core_fsm core_inst (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .req_valid_o    (core_req_valid),
        .req_addr_o     (core_req_addr),
        .req_value_o    (core_req_value),
        .req_is_fetch_o (core_req_is_fetch),
        .req_wstrb_o    (core_req_wstrb),
        .req_satp_o     (core_req_satp),
        .req_mxr_o      (core_req_mxr),
        .req_sum_o      (core_req_sum),
        .req_mprv_o     (core_req_mprv),
        .req_priv_o     (core_req_priv),
        .req_ready_i    (core_req_ready),
        
        .resp_valid_i   (core_resp_valid),
        .resp_value_i   (core_resp_value),
        .resp_ex_valid_i(core_resp_ex_valid),
        .resp_ex_code_i (core_resp_ex_code),

        .m_ext_irq_i    (m_ext_irq),
        .m_timer_irq_i  (m_timer_irq),
        .m_soft_irq_i   (m_soft_irq),
        .s_ext_irq_i    (s_ext_irq)
    );

    // ---------------------------------------------------------
    // UART (0x1000_0000)
    // ---------------------------------------------------------
    uart uart_inst (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .req_valid_i    (uart_req_valid),
        .req_addr_i     (trunc_address),
        .req_value_i    (core_req_value),
        .req_wstrb_i    (core_req_wstrb),
        
        .req_ready_o    (uart_req_ready),
        .resp_valid_o   (uart_resp_valid),
        .resp_value_o   (uart_resp_value),

        .tx_o           (uart_tx_o),
        .rx_i           (uart_rx_i),
        .uart_rx_irq_o  (uart_rx_irq)
    );

    // ---------------------------------------------------------
    // Cache (0x8000_0000)
    // ---------------------------------------------------------
    cache #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(27),
        .ID_WIDTH(4)
    ) cache_inst (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .req_valid_i    (cache_req_valid),
        .req_addr_i     (trunc_address),
        .req_value_i    (core_req_value),
        .req_wstrb_i    (core_req_wstrb),
        
        .req_ready_o    (cache_req_ready),
        .resp_valid_o   (cache_resp_valid),
        .resp_value_o   (cache_resp_value),

        // AXI Master Interface
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

    // ---------------------------------------------------------
    // XIP Flash Controller (0x9000_0000)
    // ---------------------------------------------------------
    flash_controller xip_inst (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .req_valid_i    (xip_req_valid),
        .req_addr_i     (trunc_address),
        .req_value_i    (core_req_value),
        .req_wstrb_i    (core_req_wstrb),
        
        .req_ready_o    (xip_req_ready),
        .resp_valid_o   (xip_resp_valid),
        .resp_value_o   (xip_resp_value),

        .cs_no          (spi_flash_cs_n_o),
        .sck_o          (spi_flash_sck_o),
        .mosi_o         (spi_flash_mosi_o),
        .miso_i         (spi_flash_miso_i)
    );

    // ---------------------------------------------------------
    // SPI SD (0x2000_0000)
    // ---------------------------------------------------------
    spi spi_inst (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .req_valid_i    (spi_req_valid),
        .req_addr_i     (trunc_address),
        .req_value_i    (core_req_value),
        .req_wstrb_i    (core_req_wstrb),
        
        .req_ready_o    (spi_req_ready),
        .resp_valid_o   (spi_resp_valid),
        .resp_value_o   (spi_resp_value),

        .spi_cs_n_o     (spi_sd_cs_n_o),
        .spi_sck_o      (spi_sd_sck_o),
        .spi_mosi_o     (spi_sd_mosi_o),
        .spi_miso_i     (spi_sd_miso_i)
    );

endmodule
