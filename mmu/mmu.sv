module mmu #()(
    input logic clk_i,
    input logic rst_ni,

    // Core - Bus Interface
    input  logic        req_valid_i,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_value_i,
    input  logic [3:0]  req_wstrb_i,
    input  logic        req_is_fetch_i,
    input  logic [31:0] req_satp_i,
    input  logic        req_mxr_i,
    input  logic        req_mprv_i,
    input  logic [1:0]  req_mpp_i,
    input  logic        req_sum_i,
    input  logic [1:0]  req_priv_i,

    output logic        resp_valid_o,
    output logic [31:0] resp_value_o,

    output logic        resp_ex_valid_o,
    output logic [31:0] resp_ex_code_o,

    // SoC - Bus Interface
    output logic        req_valid_o,
    output logic [31:0] req_addr_o,
    output logic [31:0] req_value_o,
    output logic [3:0]  req_wstrb_o,

    input logic        resp_valid_i,
    input logic [31:0] resp_value_i,
);
    logic actual_priv = req_priv_i == 2'b11 ? req_mprv_i : req_priv_i;


    // STATE
    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_L1,
        STATE_L1_WAIT,
        STATE_L2,
        STATE_L2_WAIT,
        STATE_RESP,
        STATE_DIRTY_WRITE,
        STATE_DIRTY_WRITE_WAIT
    } state_e;

    typedef struct packed {
        logic valid;
        logic dirty;
        logic global;
        logic accessed;
        logic [31:0] pte;
    } tlb_entry_t;

    state_e state_q = STATE_IDLE;
    state_e next_state;

    always_comb begin
        next_state = state_q;
        req_addr_o = 32'b0;
        req_value_o = 32'b0;
        req_wstrb_o = 4'b0;
        req_valid_o = 1'b0;
        if(states_q == STATE_IDLE) begin
            if(tag_hit) begin
                req_valid_o = req_valid_i;
                req_addr_o = req_addr_i;
                req_value_o = req_value_i;
                req_wstrb_o = req_wstrb_i;
            end
            resp_valid_o = resp_valid_i;
            resp_value_o = resp_value_i;
            resp_ex_valid_o = 1'b0;
            resp_ex_code_o = 32'b0;
        end
    end
endmodule
