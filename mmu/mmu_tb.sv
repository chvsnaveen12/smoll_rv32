`timescale 1ns/1ps
module mmu_tb #()(
    input logic clk_i,
    input logic rst_ni,

    // SoC - Bus Interface
    output logic        req_valid_o,
    output logic [31:0] req_addr_o,
    output logic [31:0] req_value_o,
    output logic [3:0]  req_wstrb_o,

    input  logic        req_ready_i,

    input logic        resp_valid_i,
    input logic [31:0] resp_value_i,

    // IRQ inputs (directly from C++ TB)
    input logic        m_ext_irq_i,
    input logic        m_timer_irq_i,
    input logic        m_soft_irq_i,
    input logic        s_ext_irq_i
);

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
    logic [1:0]     core_req_mpp;
    logic           core_req_ready;
    
    logic           core_resp_valid;
    logic [31:0]    core_resp_value;
    logic           core_resp_ex_valid;
    logic [31:0]    core_resp_ex_code;

    logic fence;


    mmu mmu0 (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        // Core - Bus Interface
        .req_valid_i(core_req_valid),
        .req_addr_i(core_req_addr),
        .req_value_i(core_req_value),
        .req_wstrb_i(core_req_wstrb),
        .req_is_fetch_i(core_req_is_fetch),
        .req_satp_i(core_req_satp),
        .req_mxr_i(core_req_mxr),
        .req_mprv_i(core_req_mprv),
        .req_mpp_i(core_req_mpp),
        .req_sum_i(core_req_sum),
        .req_priv_i(core_req_priv),

        .req_ready_o(core_req_ready),

        .resp_valid_o(core_resp_valid),
        .resp_value_o(core_resp_value),

        .resp_ex_valid_o(core_resp_ex_valid),
        .resp_ex_code_o(core_resp_ex_code),

        .fence_i(fence),
        .state_o(),

        // SoC - Bus Interface
        .req_valid_o(req_valid_o),
        .req_addr_o(req_addr_o),
        .req_value_o(req_value_o),
        .req_wstrb_o(req_wstrb_o),

        .req_ready_i(req_ready_i),

        .resp_valid_i(resp_valid_i),
        .resp_value_i(resp_value_i)
    );

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
        .req_mpp_o      (core_req_mpp),
        .req_priv_o     (core_req_priv),
        .req_ready_i    (core_req_ready),
        .pc_o           (),
        
        .resp_valid_i   (core_resp_valid),
        .resp_value_i   (core_resp_value),
        .resp_ex_valid_i(core_resp_ex_valid),
        .resp_ex_code_i (core_resp_ex_code),

        .fence_o(fence),

        .m_ext_irq_i    (m_ext_irq_i),
        .m_timer_irq_i  (m_timer_irq_i),
        .m_soft_irq_i   (m_soft_irq_i),
        .s_ext_irq_i    (s_ext_irq_i)
    );
endmodule