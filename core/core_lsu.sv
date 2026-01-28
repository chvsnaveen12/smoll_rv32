    // input   logic           req_ready_i,
    // input   logic           resp_valid_i,
    // input   logic [31:0]    resp_value_i,
    // input   logic           resp_ex_valid_i,
    // input   logic [31:0]    resp_ex_code_i

    // output  logic           req_valid_o,
    // output  logic [31:0]    req_addr_o,
    // output  logic [31:0]    req_value_o,
    // output  logic [3:0]     req_wstrb_o,
    // output  mmu_op_e        req_op_o,
    // output  logic [31:0]    req_satp_o,
    // output  logic           req_mxr_o,
    // output  logic           req_sum_o,
    // output  logic           req_mprv_o,
    // output  priv_e          req_priv_o,


module core_lsu import core_defs::*;#()(
    input   logic [31:0]    addr_i,
    input   mem_op_e        mem_op_i,
    input   logic [31:0]    store_data_i,
    input   logic [31:0]    resp_value_i,

    output  logic           req_valid_o,
    output  logic [31:0]    req_addr_o,
    output  logic [31:0]    req_value_o,
    output  logic [3:0]     req_wstrb_o,
    output  logic [31:0]    load_data_o
);
    logic [1:0] byte_offset;
    logic [3:0] strb;
    logic [31:0] load_data_shifted;
    logic pad;
    

    assign req_addr_o = {addr_i[31:2], 2'b00};
    assign byte_offset = addr_i[1:0];

    // Valid and strobe assertion
    always_comb begin
        case(mem_op_i)
            MEM_8, MEM_8U: begin
                req_valid_o = 1'b1;
                strb        = 4'b0001;
            end
            MEM_16, MEM_16U: begin
                req_valid_o = ~addr_i[0];
                strb        = 4'b0011;
            end
            MEM_32: begin
                req_valid_o = ~|addr_i[1:0];
                strb        = 4'b1111;
            end
            default: begin
                req_valid_o = 1'b0;
                strb        = 4'b0000;
            end
        endcase
    end

    // We'll have to right shift the load data and left shit the store data
    // Shift the load and store data
    always_comb begin
        case(byte_offset)
            2'b00:begin
                load_data_shifted   = resp_value_i;

                req_value_o     = store_data_i;
                req_wstrb_o     = strb;
            end
            2'b01:begin
                load_data_shifted   = {{8{1'b0}}, resp_value_i[31:8]};

                req_value_o     = {store_data_i[23:0], {8{1'b0}}};
                req_wstrb_o     = {strb[2:0], {1{1'b0}}};
            end
            2'b10:begin
                load_data_shifted   = {{16{1'b0}}, resp_value_i[31:16]};

                req_value_o     = {store_data_i[15:0], {16{1'b0}}};
                req_wstrb_o     = {strb[1:0], {2{1'b0}}};
            end
            2'b11:begin
                load_data_shifted   = {{24{1'b0}}, resp_value_i[31:24]};

                req_value_o     = {store_data_i[7:0], {24{1'b0}}};
                req_wstrb_o     = {strb[0], {3{1'b0}}};
            end
        endcase
    end

    // Sign extend the data
    always_comb begin
        load_data_o = 0;
        case(mem_op_i)
            MEM_8:
                load_data_o     = {{24{load_data_shifted[7]}}, load_data_shifted[7:0]};
            MEM_16:
                load_data_o     = {{16{load_data_shifted[15]}}, load_data_shifted[15:0]};
            MEM_32:
                load_data_o     = load_data_shifted;
            MEM_8U:
                load_data_o     = {{24{1'b0}}, load_data_shifted[7:0]};
            MEM_16U:
                load_data_o     = {{16{1'b0}}, load_data_shifted[15:0]};
            default: begin
            end
        endcase
    end

endmodule
