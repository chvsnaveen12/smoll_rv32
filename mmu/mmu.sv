// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Naveen Chavali

`timescale 1ns/1ps
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

    output logic        req_ready_o,

    output logic        resp_valid_o,
    output logic [31:0] resp_value_o,

    output logic        resp_ex_valid_o,
    output logic [31:0] resp_ex_code_o,

    input  logic        fence_i,

    output logic [2:0]  state_o,

    // SoC - Bus Interface
    output logic        req_valid_o,
    output logic [31:0] req_addr_o,
    output logic [31:0] req_value_o,
    output logic [3:0]  req_wstrb_o,

    input  logic        req_ready_i,

    input logic        resp_valid_i,
    input logic [31:0] resp_value_i
);

    // Latched request
    logic [31:0] req_addr_q;
    logic [31:0] req_value_q;
    logic [3:0]  req_wstrb_q;
    logic        req_is_fetch_q;
    logic [31:0] req_satp_q;
    logic        req_mxr_q;
    logic        req_mprv_q;
    logic [1:0]  req_mpp_q;
    logic        req_sum_q;
    logic [1:0]  req_priv_q;

    // State machine
    typedef enum logic [2:0] {
        STATE_IDLE_REQ,
        STATE_IDLE_RESP,
        STATE_L1_FETCH,
        STATE_L1_WAIT,
        STATE_L2_FETCH,
        STATE_L2_WAIT,
        STATE_FAULT_RESP,
        STATE_FINISH
    } state_e;

    state_e state_q /*verilator public*/ = STATE_IDLE_REQ;
    state_e next_state;

    assign state_o = state_q;

    // TLB
    typedef struct packed {
        logic valid;
        logic [31:0] satp;
        logic user;
        logic exec;
        logic read;
        logic write;
        logic [9:0] vpn1;
        logic [9:0] vpn0;
        logic [11:0] ppn1;
        logic [9:0] ppn0;
        logic megapage;
    } tlb_entry_t;

    tlb_entry_t itlb_q, dtlb_q, muxed_tlb_d;

    // Muxed signals: live inputs in IDLE_REQ, latched values otherwise
    logic        muxed_is_fetch;
    logic [3:0]  muxed_wstrb;
    logic        muxed_sum, muxed_mxr;
    logic [31:0] muxed_satp;
    logic [31:0] muxed_addr;
    logic [1:0]  muxed_priv;
    logic [1:0]  muxed_mpp;
    logic        muxed_mprv;

    assign muxed_is_fetch = state_q == STATE_IDLE_REQ ? req_is_fetch_i : req_is_fetch_q;
    assign muxed_wstrb    = state_q == STATE_IDLE_REQ ? req_wstrb_i    : req_wstrb_q;
    assign muxed_sum      = state_q == STATE_IDLE_REQ ? req_sum_i      : req_sum_q;
    assign muxed_mxr      = state_q == STATE_IDLE_REQ ? req_mxr_i      : req_mxr_q;
    assign muxed_satp     = state_q == STATE_IDLE_REQ ? req_satp_i     : req_satp_q;
    assign muxed_addr     = state_q == STATE_IDLE_REQ ? req_addr_i     : req_addr_q;
    assign muxed_priv     = state_q == STATE_IDLE_REQ ? req_priv_i     : req_priv_q;
    assign muxed_mpp      = state_q == STATE_IDLE_REQ ? req_mpp_i      : req_mpp_q;
    assign muxed_mprv     = state_q == STATE_IDLE_REQ ? req_mprv_i     : req_mprv_q;

    assign muxed_tlb_d = muxed_is_fetch ? itlb_q : dtlb_q;

    // Translation
    logic [1:0]  actual_priv;
    logic        should_translate;
    logic        tag_hit;
    logic        fault;
    logic [31:0] translated_addr, final_addr;

    assign should_translate = (actual_priv != 2'b11) && muxed_satp[31];
    assign translated_addr  = {muxed_tlb_d.ppn1[9:0],
                               muxed_tlb_d.megapage ? muxed_addr[21:12] : muxed_tlb_d.ppn0,
                               muxed_addr[11:0]};
    assign final_addr       = should_translate ? translated_addr : req_addr_i;

    // Effective privilege (MPRV)
    always_comb begin
        actual_priv = muxed_priv;
        if (muxed_priv == 2'b11 && muxed_mprv && ~muxed_is_fetch)
            actual_priv = muxed_mpp;
    end

    // Permission fault check
    always_comb begin
        fault = 1'b0;
        if (muxed_is_fetch && !muxed_tlb_d.exec)
            fault = 1'b1;
        if (~muxed_is_fetch && ~|muxed_wstrb && !muxed_tlb_d.read && (~muxed_mxr || ~muxed_tlb_d.exec))
            fault = 1'b1;
        if (|muxed_wstrb && !muxed_tlb_d.write)
            fault = 1'b1;
        if (actual_priv == 2'b10 && muxed_tlb_d.user && ~muxed_sum)
            fault = 1'b1;
        if (actual_priv == 2'b00 && ~muxed_tlb_d.user)
            fault = 1'b1;
    end

    // TLB tag match
    always_comb begin
        tag_hit = (req_addr_i[31:22] == muxed_tlb_d.vpn1)
               && (muxed_tlb_d.megapage || req_addr_i[21:12] == muxed_tlb_d.vpn0)
               && (req_satp_i[21:0] == muxed_tlb_d.satp[21:0])
               && muxed_tlb_d.valid;
        tag_hit = tag_hit || ~should_translate;
    end

    // TLB fill entry (shared between L1_WAIT and L2_WAIT)
    logic       tlb_is_mega;
    tlb_entry_t tlb_fill_d;

    assign tlb_is_mega = (state_q == STATE_L1_WAIT);

    assign tlb_fill_d = '{
        valid:    1'b1,
        satp:     req_satp_q,
        read:     resp_value_i[1],
        write:    resp_value_i[2],
        exec:     resp_value_i[3],
        user:     resp_value_i[4],
        vpn1:     req_addr_q[31:22],
        vpn0:     req_addr_q[21:12],
        ppn1:     resp_value_i[31:20],
        ppn0:     resp_value_i[19:10],
        megapage: tlb_is_mega
    };

    // Output mux
    always_comb begin
        req_ready_o     = 1'b0;
        resp_valid_o    = 1'b0;
        resp_value_o    = 32'b0;
        resp_ex_code_o  = 32'b0;
        resp_ex_valid_o = 1'b0;
        req_addr_o      = 32'b0;
        req_value_o     = 32'b0;
        req_wstrb_o     = 4'b0;
        req_valid_o     = 1'b0;
        case (state_q)
            STATE_IDLE_REQ: begin
                req_addr_o  = final_addr;
                req_value_o = req_value_i;
                req_wstrb_o = req_wstrb_i;
                req_ready_o = req_ready_i;
                if (tag_hit && (~should_translate || ~fault))
                    req_valid_o = req_valid_i;
                else
                    req_ready_o = 1'b1;
            end
            STATE_IDLE_RESP: begin
                resp_value_o = resp_value_i;
                resp_valid_o = resp_valid_i;
            end
            STATE_FAULT_RESP: begin
                resp_valid_o    = 1'b1;
                resp_ex_valid_o = 1'b1;
                resp_ex_code_o  = req_is_fetch_q ? 32'hc :
                                  |req_wstrb_q   ? 32'hf : 32'hd;
            end
            STATE_L1_FETCH: begin
                req_valid_o = 1'b1;
                req_addr_o  = {req_satp_q[19:0], req_addr_q[31:22], 2'b00};
                req_wstrb_o = 4'b0;
            end
            STATE_L1_WAIT: begin
            end
            STATE_L2_FETCH: begin
                req_valid_o = 1'b1;
                req_addr_o  = {muxed_tlb_d.ppn1[9:0], muxed_tlb_d.ppn0[9:0], req_addr_q[21:12], 2'b00};
                req_wstrb_o = 4'b0;
            end
            STATE_L2_WAIT: begin
            end
            STATE_FINISH: begin
                req_addr_o  = final_addr;
                req_value_o = req_value_q;
                req_wstrb_o = req_wstrb_q;
                if (~fault)
                    req_valid_o = 1'b1;
            end
        endcase
    end

    // Next state logic
    always_comb begin
        next_state = STATE_FAULT_RESP;
        case (state_q)
            STATE_IDLE_REQ: begin
                if (tag_hit)
                    next_state = (should_translate && fault) ? STATE_FAULT_RESP : STATE_IDLE_RESP;
                else
                    next_state = STATE_L1_FETCH;
            end
            STATE_IDLE_RESP:
                next_state = STATE_IDLE_REQ;
            STATE_L1_FETCH:
                next_state = STATE_L1_WAIT;
            STATE_L1_WAIT: begin
                if (~resp_value_i[0])
                    next_state = STATE_FAULT_RESP;
                else
                    next_state = |resp_value_i[3:1] ? STATE_FINISH : STATE_L2_FETCH;
            end
            STATE_L2_FETCH:
                next_state = STATE_L2_WAIT;
            STATE_L2_WAIT: begin
                if (~resp_value_i[0])
                    next_state = STATE_FAULT_RESP;
                else
                    next_state = STATE_FINISH;
            end
            STATE_FINISH:
                next_state = fault ? STATE_FAULT_RESP : STATE_IDLE_RESP;
            STATE_FAULT_RESP:
                next_state = STATE_IDLE_REQ;
            default: begin
            end
        endcase
    end

    // Sequential logic
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= STATE_IDLE_REQ;
            itlb_q  <= '0;
            dtlb_q  <= '0;
        end
        else begin
            if (fence_i) begin
                itlb_q.valid <= 1'b0;
                dtlb_q.valid <= 1'b0;
            end

            case (state_q)
                STATE_IDLE_REQ: begin
                    if (req_valid_i) begin
                        if (tag_hit && (~should_translate || ~fault)) begin
                            if (req_ready_i) state_q <= next_state;
                        end else begin
                            state_q <= next_state;
                        end
                        req_addr_q     <= req_addr_i;
                        req_value_q    <= req_value_i;
                        req_wstrb_q    <= req_wstrb_i;
                        req_is_fetch_q <= req_is_fetch_i;
                        req_satp_q     <= req_satp_i;
                        req_mxr_q      <= req_mxr_i;
                        req_mprv_q     <= req_mprv_i;
                        req_mpp_q      <= req_mpp_i;
                        req_sum_q      <= req_sum_i;
                        req_priv_q     <= req_priv_i;
                    end
                end
                STATE_IDLE_RESP: begin
                    if (resp_valid_i)
                        state_q <= next_state;
                end
                STATE_L1_FETCH: begin
                    if (req_ready_i)
                        state_q <= next_state;
                end
                STATE_L1_WAIT: begin
                    if (resp_valid_i)
                        state_q <= next_state;
                    if (muxed_is_fetch) itlb_q <= tlb_fill_d;
                    else               dtlb_q <= tlb_fill_d;
                end
                STATE_L2_FETCH: begin
                    if (req_ready_i)
                        state_q <= next_state;
                end
                STATE_L2_WAIT: begin
                    if (resp_valid_i)
                        state_q <= next_state;
                    if (muxed_is_fetch) itlb_q <= tlb_fill_d;
                    else               dtlb_q <= tlb_fill_d;
                end
                STATE_FAULT_RESP: begin
                    state_q <= next_state;
                end
                STATE_FINISH: begin
                    if (fault || req_ready_i)
                        state_q <= next_state;
                end
                default: begin
                end
            endcase
        end
    end
endmodule
