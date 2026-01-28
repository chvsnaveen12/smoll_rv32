module core_fsm import core_defs::*;#()(
    // Global signals
    input   logic       clk_i,
    input   logic       rst_ni,

    // Control to MMU
    output  logic           req_valid_o,
    output  logic [31:0]    req_addr_o,
    output  logic [31:0]    req_value_o,
    output  logic           req_is_fetch_o,
    output  logic [3:0]     req_wstrb_o,
    output  logic [31:0]    req_satp_o,
    output  logic           req_mxr_o,
    output  logic           req_sum_o,
    output  logic           req_mprv_o,
    output  logic           req_mpp_o,
    output  logic [1:0]     req_priv_o,
    input   logic           req_ready_i,

    input   logic           resp_valid_i,
    input   logic [31:0]    resp_value_i,
    input   logic           resp_ex_valid_i,
    input   logic [31:0]    resp_ex_code_i,

    // Pending interrupts
    input   logic           m_ext_irq_i,
    input   logic           m_timer_irq_i,
    input   logic           m_soft_irq_i,
    input   logic           s_ext_irq_i
);
    // FSM ===================================================== 
    typedef enum logic [3:0] {
        STATE_FETCH         = 4'b0000,
        STATE_FETCH_WAIT    = 4'b0001,
        STATE_DECODE        = 4'b0010,
        STATE_EXECUTE       = 4'b0011,
        STATE_MEM           = 4'b0100,
        STATE_MEM_WAIT      = 4'b0101,
        STATE_WRITEBACK     = 4'b0110,
        STATE_SYSTEM        = 4'b0111,
        STATE_FENCE         = 4'b1000,
        STATE_TRAP          = 4'b1001,
        STATE_INT           = 4'b1010
    } state_e;
    state_e state_q /*verilator public*/ = STATE_FETCH, next_state /*verilator public*/;
    // =========================================================


    // Registers used in between stages ========================
    
    // Global variables
    logic           global_ex_valid;
    logic [31:0]    global_ex_code_q;
    logic [31:0]    global_ex_tval_q;

    logic [31:0]    global_debug_cycle_q;

    // Fetch to Decode
    logic [31:0]    fe_instr_q;
    logic [31:0]    fe_pc_q;
    logic [31:0]    fe_npc_q;


    // Decode to execute
    logic [31:0]    de_rs1_q;
    logic [31:0]    de_rs2_q;
    logic [31:0]    de_immediate_q;
    logic [31:0]    de_pc_q;
    logic           de_use_pc_q;
    logic           de_use_imm_q;
    op_type_e       de_op_type_q;
    priv_op_e       de_priv_op_q;
    logic [2:0]     de_funct3_q;
    logic           de_arith_sub_q;
    logic [31:0]    de_npc_q;
    logic [4:0]     de_rd_sel_q;
    logic [11:0]    de_csr_addr_q;
    logic [31:0]    de_csr_rdata_q;
    logic           de_csr_rvalid_q;
    logic [31:0]    de_csr_uimm_q;
    logic           de_csr_wen_q;

    // Excute to Mem or WB
    logic [31:0]    ex_output_q;
    logic [31:0]    ex_sum_q;
    logic           ex_branch_flag_q;
    logic [31:0]    ex_rs2_q;
    op_type_e       ex_op_type_q;
    priv_op_e       ex_priv_op_e;
    logic [31:0]    ex_npc_q;
    logic [4:0]     ex_rd_sel_q;
    logic [2:0]     ex_funct3_q;
    logic [11:0]    ex_csr_addr_q;
    logic [31:0]    ex_csr_rdata_q;
    logic           ex_csr_rvalid_q;
    logic           ex_csr_wen_q;
    logic [31:0]    ex_csr_wdata_q;

    // Mem to WB
    logic [31:0]    mem_data_q;
    // =========================================================


    // Decoding stage ==========================================
    logic           decoder_valid;
    logic [4:0]     decoder_rs1_sel;
    logic [4:0]     decoder_rs2_sel;
    logic [4:0]     decoder_rd_sel;
    logic [31:0]    decoder_immediate;
    logic           decoder_use_pc;
    logic           decoder_use_imm;
    op_type_e       decoder_op_type;
    priv_op_e       decoder_priv_op;
    logic [2:0]     decoder_funct3;
    logic           decoder_arith_sub;
    logic           decoder_ebreak_sel;
    logic [11:0]    decoder_csr_addr;
    logic [31:0]    decoder_csr_uimm;
    logic           decoder_csr_wen;

    logic [31:0]    regs_rs1;
    logic [31:0]    regs_rs2;

    logic [4:0]     regs_waddr;
    logic [31:0]    regs_wdata;

    logic [31:0]    csrs_rdata;
    logic           csrs_rvalid;

    logic [11:0]    csrs_waddr;
    logic [31:0]    csrs_wdata;
    logic           csrs_exception;
    logic [31:0]    csrs_exception_code;
    logic [31:0]    csrs_exception_tval;
    logic [31:0]    csrs_instr_pc;

    logic           csrs_mret;
    logic           csrs_sret;

    logic           csrs_int_bool;
    logic           csrs_int_take;

    logic [31:0]    csrs_satp;
    logic           csrs_mxr;
    logic           csrs_sum;
    logic           csrs_mprv;
    priv_e          csrs_priv;

    logic [31:0]    csrs_updated_pc;

    core_decoder decoder(
        .instr_i(fe_instr_q),
        .pc_i(fe_pc_q),
        .priv_i(csrs_priv),

        .valid_o(decoder_valid),
        .rs1_sel_o(decoder_rs1_sel),
        .rs2_sel_o(decoder_rs2_sel),
        .rd_sel_o(decoder_rd_sel),
        .immediate_o(decoder_immediate),
        .use_pc_o(decoder_use_pc),
        .use_imm_o(decoder_use_imm),
        .op_type_o(decoder_op_type),
        .priv_op_o(decoder_priv_op),
        .funct3_o(decoder_funct3),
        .arith_sub_o(decoder_arith_sub),
        
        .csr_addr_o(decoder_csr_addr),
        .csr_uimm_o(decoder_csr_uimm)
    );

    core_regs regs(
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .raddr_a_i(decoder_rs1_sel),
        .raddr_b_i(decoder_rs2_sel),

        .waddr_i(regs_waddr),
        .wdata_i(regs_wdata),

        .rdata_a_o(regs_rs1),
        .rdata_b_o(regs_rs2)
    );

    core_csrs csrs(
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .raddr_i(decoder_csr_addr),
        .rdata_o(csrs_rdata),
        .rvalid_o(csrs_rvalid),

        .waddr_i(csrs_waddr),
        .wdata_i(csrs_wdata),

        .exception_i(csrs_exception),
        .exception_code_i(global_ex_code_q),
        .exception_tval_i(global_ex_tval_q),
        .instr_pc_i(pc_q),
        
        .mret_i(csrs_mret),
        .sret_i(csrs_sret),

        .int_bool_o(csrs_int_bool),
        .int_take_i(csrs_int_take),

        .m_ext_irq_i(m_ext_irq_i),
        .m_timer_irq_i(m_timer_irq_i),
        .m_soft_irq_i(m_soft_irq_i),
        .s_ext_irq_i(s_ext_irq_i),

        .satp_o(req_satp_o),
        .mxr_o(req_mxr_o),
        .sum_o(req_sum_o),
        .mprv_o(req_mprv_o),
        .priv_o(csrs_priv),

        .updated_pc_o(csrs_updated_pc)
    );

    // =========================================================

    // Execute stage ===========================================
    logic [31:0]    alu_output;
    logic [31:0]    alu_sum;
    logic           alu_branch_flag;
    logic [31:0]    alu_csr_wdata;

    core_alu alu(
        .rs1_i(de_rs1_q),
        .rs2_i(de_rs2_q),
        .immediate_i(de_immediate_q),
        .pc_i(de_pc_q),
        .use_pc_i(de_use_pc_q),
        .use_imm_i(de_use_imm_q),
        .arith_sub_i(de_arith_sub_q),
        .funct3_i(de_funct3_q),

        .csr_rdata_i(de_csr_rdata_q),
        .csr_uimm_i(de_csr_uimm_q),

        .output_o(alu_output),
        .sum_o(alu_sum),
        .branch_flag_o(alu_branch_flag),

        .csr_wdata_o(alu_csr_wdata)
    );
    // =========================================================

    // Memory stage ============================================
    logic           lsu_req_valid;
    logic [31:0]    lsu_req_addr;
    logic [31:0]    lsu_req_value;
    logic [3:0]     lsu_req_wstrb;
    logic [31:0]    lsu_load_data; 

    core_lsu lsu(
        .addr_i(ex_sum_q),
        .mem_op_i(mem_op_e'(ex_funct3_q)),
        .store_data_i(ex_rs2_q),
        .resp_value_i(resp_value_i),

        .req_valid_o(lsu_req_valid),
        .req_addr_o(lsu_req_addr),
        .req_value_o(lsu_req_value),
        .req_wstrb_o(lsu_req_wstrb),
        .load_data_o(lsu_load_data)
    );
    // =========================================================




    // State
    logic [31:0] pc_q = 0, npc;

    // always_ff @(posedge clk_i) begin
        // if (!rst_ni) begin
            // state_q <= STATE_FETCH;
        // end
        // state_q <= next_state;
    // end


    // Main fsm
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            global_debug_cycle_q <= 0;
            state_q <= STATE_FETCH;
            pc_q    <= 32'h40000000;
        end
        else
            state_q <= next_state;
        case(state_q)
            STATE_FETCH: begin
                if(rst_ni) begin
                    global_debug_cycle_q    <= global_debug_cycle_q + 1;
                end else begin
                    global_debug_cycle_q    <= 0;
                end
            end
            STATE_FETCH_WAIT: begin
                fe_instr_q          <= resp_value_i;
                fe_pc_q             <= pc_q;
                fe_npc_q            <= pc_q + 4;

                global_ex_code_q    <= resp_ex_code_i;
                global_ex_tval_q    <= pc_q;
            end
            STATE_DECODE: begin
                de_rs1_q            <= regs_rs1;
                de_rs2_q            <= regs_rs2;
                de_immediate_q      <= decoder_immediate;
                de_pc_q             <= fe_pc_q;
                de_use_pc_q         <= decoder_use_pc;
                de_use_imm_q        <= decoder_use_imm;
                de_op_type_q        <= decoder_op_type;
                de_priv_op_q        <= decoder_priv_op;
                de_funct3_q         <= decoder_funct3;
                de_arith_sub_q      <= decoder_arith_sub;
                de_npc_q            <= fe_npc_q;
                de_rd_sel_q         <= decoder_rd_sel;
                de_csr_addr_q       <= decoder_csr_addr;
                de_csr_rdata_q      <= csrs_rdata;
                de_csr_uimm_q       <= decoder_csr_uimm;
                de_csr_rvalid_q     <= csrs_rvalid;
                de_csr_wen_q        <= |decoder_csr_uimm;

                global_ex_code_q    <= 32'h2;                 // Illegal instruction
                
                // $display("DEC: PC=%h, RS1=%d Val=%h, RS2=%d Val=%h", fe_pc_q, decoder_rs1_sel, regs_rs1, decoder_rs2_sel, regs_rs2);
            end
            STATE_EXECUTE: begin
                ex_output_q         <= alu_output;
                ex_sum_q            <= alu_sum;
                ex_branch_flag_q    <= alu_branch_flag;
                ex_rs2_q            <= de_rs2_q;
                ex_op_type_q        <= de_op_type_q;
                ex_priv_op_e        <= de_priv_op_q;
                ex_npc_q            <= de_npc_q;
                ex_rd_sel_q         <= de_rd_sel_q;
                ex_funct3_q         <= de_funct3_q;
                ex_csr_addr_q       <= de_csr_addr_q;
                ex_csr_rdata_q      <= de_csr_rdata_q;
                ex_csr_rvalid_q     <= de_csr_rvalid_q;
                ex_csr_wen_q        <= de_csr_wen_q;
                ex_csr_wdata_q      <= alu_csr_wdata;
            end
            STATE_MEM: begin
                global_ex_code_q    <= ex_op_type_q == OP_LOAD ? 32'h4 : 32'h6;    // Load or store address misaligned
                global_ex_tval_q    <= ex_sum_q;
            end
            STATE_MEM_WAIT: begin
                mem_data_q          <= lsu_load_data;
                global_ex_code_q    <= resp_ex_code_i;
                global_ex_tval_q    <= ex_sum_q;
            end
            STATE_WRITEBACK: begin
                pc_q <= npc;
            end
            STATE_SYSTEM: begin
                case(sys_op_e'(ex_funct3_q))
                    SYS_PRIV: begin
                        case(ex_priv_op_e)
                            PRIVOP_EBREAK:
                                global_ex_code_q    <= 32'h3;
                            PRIVOP_ECALL:
                                global_ex_code_q    <= csrs_priv == PRIV_MACHINE ? 32'hb : (csrs_priv == PRIV_SUPERVISOR ? 32'h9 : 32'h8);
                            PRIVOP_MRET, PRIVOP_SRET:
                                pc_q                <= csrs_updated_pc;
                            default: begin
                            end
                        endcase
                    end
                    SYS_CSRRW, SYS_CSRRWI, SYS_CSRRS, SYS_CSRRSI, SYS_CSRRC, SYS_CSRRCI: begin
                        if(ex_csr_rvalid_q)
                            pc_q <= npc;
                    end
                    default: begin
                    end
                endcase
            end
            STATE_TRAP: begin
                pc_q <= csrs_updated_pc; 
            end
            STATE_FENCE: begin
                pc_q <= npc;
            end
            STATE_INT: begin
                pc_q <= csrs_updated_pc;
            end
        default : $error("bad case");
        endcase
    end

    // // System ops
    // always_comb begin
    //     csrs_waddr = 0;
    //     if(state_q == STATE_SYSTEM) begin
    //         case(sys_op_e'(ex_funct3_q))
    //             SYS_CSRRW, SYS_CSRRS, SYS_CSRRC, SYS_CSRRWI, SYS_CSRRSI, SYS_CSRRCI: begin
    //                 csrs_waddr = ex_csr_wen_q ? ex_csr_addr_q : 12'b0;
    //             end
    //             default: begin
    //             end
    //         endcase
    //     end
    // end

    // Normal and CSR Write back
    always_comb begin
        regs_waddr = 0;
        regs_wdata = 0;

        csrs_waddr = 0;
        csrs_wdata = 0;

        if(state_q == STATE_WRITEBACK) begin
            case(ex_op_type_q)
                OP_ALU: begin
                    regs_waddr = ex_rd_sel_q;
                    regs_wdata = ex_output_q;
                end
                OP_LUI_AUIPC: begin
                    regs_waddr = ex_rd_sel_q;
                    regs_wdata = ex_sum_q;
                end
                OP_JUMP: begin
                    regs_waddr = ex_rd_sel_q;
                    regs_wdata = ex_npc_q;
                end
                OP_LOAD: begin
                    regs_waddr = ex_rd_sel_q;
                    regs_wdata = mem_data_q;
                end
                default: begin
                end
            endcase
        end
        else if(state_q == STATE_SYSTEM && (sys_op_e'(ex_funct3_q[1:0]) != SYS_PRIV)) begin
            regs_waddr = ex_rd_sel_q;
            regs_wdata = ex_csr_rdata_q;

            csrs_waddr = ex_csr_wen_q ? ex_csr_addr_q : 0;
            csrs_wdata = ex_csr_wdata_q;
        end
        
        // if(state_q == STATE_WRITEBACK && regs_waddr != 0)
        //     // $display("WB_FINAL: PC=%h, RD=%d, Data=%h", pc_q, regs_waddr, regs_wdata);
    end

    // NPC logic
    always_comb begin
        npc = 0;
        case(ex_op_type_q)
            OP_ALU, OP_LOAD, OP_STORE, OP_LUI_AUIPC, OP_FENCE, OP_SYSTEM:
                npc = ex_npc_q;
            OP_JUMP:
                npc = ex_sum_q;
            OP_BRANCH:
                npc = ex_branch_flag_q ? ex_sum_q : ex_npc_q;
            default: begin
            end
        endcase
    end

    // Next state and logic assignments
    always_comb begin
        csrs_mret = 0;
        csrs_exception = 0;
        csrs_int_take = 0;
        csrs_sret = 0;
        global_ex_valid = 0;
        next_state = STATE_SYSTEM;
        case(state_q)
            STATE_FETCH: begin
                global_ex_valid = |pc_q[1:0];
                next_state = req_ready_i ? STATE_FETCH_WAIT : STATE_FETCH;
            end
            STATE_FETCH_WAIT: begin
                if(resp_valid_i)
                    global_ex_valid = resp_ex_valid_i;
 
                next_state = resp_valid_i ? STATE_DECODE : STATE_FETCH_WAIT;
            end
            STATE_DECODE: begin
                global_ex_valid = !decoder_valid;
                next_state = STATE_EXECUTE;
            end
            STATE_EXECUTE: begin
                case(de_op_type_q)
                    OP_LOAD, OP_STORE:
                        next_state = STATE_MEM;
                    OP_SYSTEM:
                        next_state = STATE_SYSTEM;
                    OP_FENCE:
                        next_state = STATE_FENCE;
                    default:
                        next_state = STATE_WRITEBACK;
                endcase
            end
            STATE_MEM: begin
                global_ex_valid = !lsu_req_valid;
                next_state = req_ready_i ? STATE_MEM_WAIT : STATE_MEM;
            end

            STATE_MEM_WAIT: begin
                if(resp_valid_i)
                    global_ex_valid = resp_ex_valid_i;
                next_state = resp_valid_i ? STATE_WRITEBACK : STATE_MEM_WAIT;
            end

            STATE_WRITEBACK: begin
                next_state = csrs_int_bool ? STATE_INT : STATE_FETCH;
            end
            STATE_SYSTEM: begin
                next_state = STATE_FETCH;
                case(sys_op_e'(ex_funct3_q))
                    SYS_PRIV: begin
                        case(ex_priv_op_e)
                            PRIVOP_EBREAK, PRIVOP_ECALL:
                                global_ex_valid = 1'b1;
                            PRIVOP_MRET:
                                csrs_mret = 1;
                            PRIVOP_SRET:
                                csrs_sret = 1;
                        endcase
                    end
                    SYS_CSRRW, SYS_CSRRWI, SYS_CSRRS, SYS_CSRRSI, SYS_CSRRC, SYS_CSRRCI:
                        global_ex_valid = !ex_csr_rvalid_q;
                    default: begin
                    end
                endcase
            end
            STATE_FENCE:
                next_state = STATE_FETCH;
            STATE_INT: begin
                next_state = STATE_FETCH;
                csrs_int_take = 1;
            end
            STATE_TRAP: begin
                next_state = STATE_FETCH;
                csrs_exception = 1;
            end
            default : $error("bad case");
        endcase

        if(global_ex_valid)
            next_state = STATE_TRAP;
    end

    // Memory requests
    always_comb begin
        // Defaults
        req_valid_o     = 0;
        req_addr_o      = 0;
        req_value_o     = 0;
        req_wstrb_o     = 0;
        req_is_fetch_o  = 0;

        // req_satp_o      = csrs_satp;
        // req_mxr_o       = csrs_mxr;
        // req_sum_o       = csrs_sum;
        // req_mprv_o      = csrs_mprv;
        // req_priv_o      = csrs_priv;

        case(state_q)
            STATE_FETCH: begin
                req_valid_o     = !rst_ni ? 0 : 1;
                req_addr_o      = pc_q;
                req_is_fetch_o  = 1;
            end
            STATE_MEM: begin
                req_valid_o     = lsu_req_valid;
                req_addr_o      = lsu_req_addr;
                req_value_o     = lsu_req_value;
                req_wstrb_o     = (ex_op_type_q == OP_STORE) ? lsu_req_wstrb : 4'b0;
            end
            default:
                req_valid_o     = 0;
        endcase
    end
endmodule
