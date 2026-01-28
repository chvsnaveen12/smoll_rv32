`timescale 1ns / 1ps

module cache #(
    parameter READ_ONLY = 0,
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 27,
    // Width of wstrb (width of data bus in words)
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    // Width of ID signal
    parameter ID_WIDTH = 4
) (
    // Global
    input  logic       clk_i,
    input  logic       rst_ni,
    
    // Bus
    input  logic           req_valid_i,
    input  logic [31:0]    req_value_i,
    input  logic [31:0]    req_addr_i,
    input  logic [3:0]     req_wstrb_i,
    output logic           req_ready_o,
    
    output logic           resp_valid_o,
    output logic [31:0]    resp_value_o,

    // MIG
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
    // General bs
    assign m_axi_awlock     = 1'b0;
    assign m_axi_awcache    = 4'b0000;
    assign m_axi_awprot     = 3'b000;
    assign m_axi_arlock     = 1'b0;
    assign m_axi_arcache    = 4'b0000;
    assign m_axi_arprot     = 3'b000;
    assign m_axi_bready     = 1'b1;


    // These are specific to our bursting requests
    assign m_axi_awid       = {ID_WIDTH{1'b0}};
    assign m_axi_awsize     = 3'b010;
    assign m_axi_awlen      = 8'b00001111;
    assign m_axi_awburst    = 2'b01;
    
    assign m_axi_wstrb      = 4'b1111;

    assign m_axi_arid       = {ID_WIDTH{1'b0}};
    assign m_axi_arsize     = 3'b010;
    assign m_axi_arlen      = 8'b00001111;
    assign m_axi_arburst    = 2'b01;


    // Cache
    logic [5:0] req_offset, latched_req_offset;
    logic [5:0] req_index, latched_req_index;
    logic [19:0] req_tag, latched_req_tag, latched_return_tag;
    logic [31:0] data_ram [0:1023];
    logic [19:0] tag_ram [0:63];
    logic tag_hit;
    logic [3:0] latched_wstrb;
    logic [31:0] latched_value;

    assign req_offset = req_addr_i[5:0];
    assign req_index = req_addr_i[11:6];
    assign req_tag = req_addr_i[31:12];



    assign tag_hit = tag_ram[req_index] == req_tag;

    logic [3:0] count;

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
        m_axi_wvalid <= 1'b0;
        m_axi_wlast <= 1'b0;
        if(!rst_ni) begin
            state_q <= STATE_IDLE;
            for(integer i = 0; i < 64; i++) begin
                tag_ram[i] <= 20'h00000;
            end
        end else begin
            resp_valid_o <= 0;
            case(state_q)
                STATE_IDLE: begin
                    req_ready_o <= 1;
                    if(req_valid_i) begin
                        if(!tag_hit) begin
                            state_q <= STATE_WRITE_ADDR;
                            latched_req_index <= req_index;
                            latched_req_offset <= req_offset;
                            latched_req_tag <= req_tag;
                            latched_wstrb <= req_wstrb_i;
                            latched_value <= req_value_i;
                            req_ready_o <= 0;
                            // tag_ram[req_index] <= req_tag;
                            // m_axi_awaddr <= {tag_ram[req_index], req_index, 6'b000000};
                            // m_axi_awvalid <= 1'b1;
                        end else begin
                            if(req_wstrb_i[0]) data_ram[{req_index, req_offset[5:2]}][7:0] <= req_value_i[7:0];
                            if(req_wstrb_i[1]) data_ram[{req_index, req_offset[5:2]}][15:8] <= req_value_i[15:8];
                            if(req_wstrb_i[2]) data_ram[{req_index, req_offset[5:2]}][23:16] <= req_value_i[23:16];
                            if(req_wstrb_i[3]) data_ram[{req_index, req_offset[5:2]}][31:24] <= req_value_i[31:24];
                            resp_valid_o <= 1;
                            resp_value_o <= data_ram[{req_index, req_offset[5:2]}];
                        end
                    end
                end
                STATE_WRITE_ADDR: begin
                    m_axi_awaddr <= {tag_ram[latched_req_index], latched_req_index, 6'b000000};
                    m_axi_awvalid <= 1'b1;
                    if(m_axi_awready && m_axi_awvalid) begin
                        state_q <= STATE_WRITE_DATA;
                        count <= 1;
                        // m_axi_wvalid <= 1;
                        // m_axi_wdata <= data_ram[{latched_req_index, 4'b0000}];
                    end
                end
                STATE_WRITE_DATA: begin
                    m_axi_wdata <= data_ram[{latched_req_index, 4'b0000}];
                    m_axi_wvalid <= 1'b1;
                    m_axi_wlast <= 1'b0;
                    if(m_axi_wready && m_axi_wvalid) begin
                        m_axi_wdata <= data_ram[{latched_req_index, count}];
                        count <= count + 1;
                        if(count == 15) begin
                            state_q <= STATE_READ_ADDR;
                            m_axi_wlast <= 1'b1;
                            // m_axi_araddr <= {latched_req_tag, latched_req_index, 6'b000000};
                            // m_axi_arvalid <= 1'b1;
                        end
                    end
                end
                STATE_READ_ADDR: begin
                    m_axi_araddr <= {latched_req_tag, latched_req_index, 6'b000000};
                    m_axi_arvalid <= 1'b1;
                    if(m_axi_arready && m_axi_arvalid) begin
                        state_q <= STATE_READ_DATA;
                        count <= 0;
                    end
                end
                STATE_READ_DATA: begin
                    m_axi_rready <= 1'b1;
                    if(m_axi_rvalid && m_axi_rready) begin
                        data_ram[{latched_req_index, count}] <= m_axi_rdata;
                        count <= count + 1;
                        if(m_axi_rlast)
                            state_q <= STATE_FINISH;
                    end
                end
                STATE_FINISH: begin
                    tag_ram[latched_req_index] <= latched_req_tag;
                    state_q <= STATE_IDLE;
                    if(latched_wstrb[0]) 
                        data_ram[{latched_req_index, latched_req_offset[5:2]}][7:0] <= latched_value[7:0];
                    if(latched_wstrb[1])
                        data_ram[{latched_req_index, latched_req_offset[5:2]}][15:8] <= latched_value[15:8];
                    if(latched_wstrb[2])
                        data_ram[{latched_req_index, latched_req_offset[5:2]}][23:16] <= latched_value[23:16];
                    if(latched_wstrb[3])
                        data_ram[{latched_req_index, latched_req_offset[5:2]}][31:24] <= latched_value[31:24];
                    resp_valid_o <= 1;
                    resp_value_o <= data_ram[{latched_req_index, latched_req_offset[5:2]}];
                    req_ready_o <= 1;
                end
                default: begin
                end
            endcase
        end
    end
    
endmodule