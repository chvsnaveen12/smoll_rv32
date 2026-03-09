`timescale 1ns / 1ps

module cache #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 27,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH = 4
) (
    input  logic       clk_i,
    input  logic       rst_ni,

    // SoC Bus
    input  logic           req_valid_i,
    input  logic [31:0]    req_value_i,
    input  logic [31:0]    req_addr_i,
    input  logic [3:0]     req_wstrb_i,
    output logic           req_ready_o,

    output logic           resp_valid_o,
    output logic [31:0]    resp_value_o,

    // AXI Master
    output logic [ID_WIDTH-1:0]    m_axi_awid,
    output logic [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic                   m_axi_awlock,
    output logic [3:0]             m_axi_awcache,
    output logic [2:0]             m_axi_awprot,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,

    output logic [DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [STRB_WIDTH-1:0]  m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,

    input  logic [ID_WIDTH-1:0]    m_axi_bid,
    input  logic [1:0]             m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,

    output logic [ID_WIDTH-1:0]    m_axi_arid,
    output logic [ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arlock,
    output logic [3:0]             m_axi_arcache,
    output logic [2:0]             m_axi_arprot,
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,

    input  logic [ID_WIDTH-1:0]    m_axi_rid,
    input  logic [DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]             m_axi_rresp,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready
);

    // AXI constants
    assign m_axi_awlock     = 1'b0;
    assign m_axi_awcache    = 4'b0000;
    assign m_axi_awprot     = 3'b000;
    assign m_axi_arlock     = 1'b0;
    assign m_axi_arcache    = 4'b0000;
    assign m_axi_arprot     = 3'b000;
    assign m_axi_bready     = 1'b1;

    // Burst config: 16-beat INCR, 4 bytes each
    assign m_axi_awid       = {ID_WIDTH{1'b0}};
    assign m_axi_awsize     = 3'b010;
    assign m_axi_awlen      = 8'd15;
    assign m_axi_awburst    = 2'b01;
    assign m_axi_wstrb      = 4'b1111;
    assign m_axi_arid       = {ID_WIDTH{1'b0}};
    assign m_axi_arsize     = 3'b010;
    assign m_axi_arlen      = 8'd15;
    assign m_axi_arburst    = 2'b01;

    // Cache storage
    logic [31:0] data_ram [0:1023];
    logic [19:0] tag_ram  [0:63];

    // Address decode
    logic [5:0]  req_offset, req_offset_q;
    logic [5:0]  req_index,  req_index_q;
    logic [19:0] req_tag,    req_tag_q;
    logic        tag_hit;

    assign req_offset = req_addr_i[5:0];
    assign req_index  = req_addr_i[11:6];
    assign req_tag    = req_addr_i[31:12];
    assign tag_hit    = tag_ram[req_index] == req_tag;

    // Latched request
    logic [3:0]  req_wstrb_q;
    logic [31:0] req_value_q;
    logic [3:0]  count_q;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_WRITE_ADDR,
        STATE_WRITE_DATA,
        STATE_READ_ADDR,
        STATE_READ_DATA,
        STATE_FINISH
    } state_e;

    state_e state_q;

    always_ff @(posedge clk_i) begin
        m_axi_awvalid <= 1'b0;
        m_axi_arvalid <= 1'b0;
        m_axi_wvalid  <= 1'b0;
        m_axi_wlast   <= 1'b0;
        if(!rst_ni) begin
            state_q <= STATE_IDLE;
            for(integer i = 0; i < 64; i++)
                tag_ram[i] <= 20'h00000;
        end else begin
            resp_valid_o <= 0;
            case(state_q)
                STATE_IDLE: begin
                    req_ready_o <= 1;
                    if(req_valid_i) begin
                        if(!tag_hit) begin
                            state_q       <= STATE_WRITE_ADDR;
                            req_index_q   <= req_index;
                            req_offset_q  <= req_offset;
                            req_tag_q     <= req_tag;
                            req_wstrb_q   <= req_wstrb_i;
                            req_value_q   <= req_value_i;
                            req_ready_o   <= 0;
                        end else begin
                            if(req_wstrb_i[0]) data_ram[{req_index, req_offset[5:2]}][7:0]   <= req_value_i[7:0];
                            if(req_wstrb_i[1]) data_ram[{req_index, req_offset[5:2]}][15:8]  <= req_value_i[15:8];
                            if(req_wstrb_i[2]) data_ram[{req_index, req_offset[5:2]}][23:16] <= req_value_i[23:16];
                            if(req_wstrb_i[3]) data_ram[{req_index, req_offset[5:2]}][31:24] <= req_value_i[31:24];
                            resp_valid_o <= 1;
                            resp_value_o <= data_ram[{req_index, req_offset[5:2]}];
                        end
                    end
                end
                STATE_WRITE_ADDR: begin
                    m_axi_awaddr  <= {tag_ram[req_index_q], req_index_q, 6'b000000};
                    m_axi_awvalid <= 1'b1;
                    if(m_axi_awready && m_axi_awvalid) begin
                        state_q  <= STATE_WRITE_DATA;
                        count_q  <= 1;
                    end
                end
                STATE_WRITE_DATA: begin
                    m_axi_wdata  <= data_ram[{req_index_q, 4'b0000}];
                    m_axi_wvalid <= 1'b1;
                    m_axi_wlast  <= 1'b0;
                    if(m_axi_wready && m_axi_wvalid) begin
                        m_axi_wdata <= data_ram[{req_index_q, count_q}];
                        count_q     <= count_q + 1;
                        if(count_q == 15) begin
                            state_q      <= STATE_READ_ADDR;
                            m_axi_wlast  <= 1'b1;
                        end
                    end
                end
                STATE_READ_ADDR: begin
                    m_axi_araddr  <= {req_tag_q, req_index_q, 6'b000000};
                    m_axi_arvalid <= 1'b1;
                    if(m_axi_arready && m_axi_arvalid) begin
                        state_q <= STATE_READ_DATA;
                        count_q <= 0;
                    end
                end
                STATE_READ_DATA: begin
                    m_axi_rready <= 1'b1;
                    if(m_axi_rvalid && m_axi_rready) begin
                        data_ram[{req_index_q, count_q}] <= m_axi_rdata;
                        count_q <= count_q + 1;
                        if(m_axi_rlast)
                            state_q <= STATE_FINISH;
                    end
                end
                STATE_FINISH: begin
                    tag_ram[req_index_q] <= req_tag_q;
                    state_q <= STATE_IDLE;
                    if(req_wstrb_q[0]) data_ram[{req_index_q, req_offset_q[5:2]}][7:0]   <= req_value_q[7:0];
                    if(req_wstrb_q[1]) data_ram[{req_index_q, req_offset_q[5:2]}][15:8]  <= req_value_q[15:8];
                    if(req_wstrb_q[2]) data_ram[{req_index_q, req_offset_q[5:2]}][23:16] <= req_value_q[23:16];
                    if(req_wstrb_q[3]) data_ram[{req_index_q, req_offset_q[5:2]}][31:24] <= req_value_q[31:24];
                    resp_valid_o <= 1;
                    resp_value_o <= data_ram[{req_index_q, req_offset_q[5:2]}];
                    req_ready_o  <= 1;
                end
                default: begin
                end
            endcase
        end
    end

endmodule
