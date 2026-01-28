`timescale 1ns/1ps
module core_decoder import core_defs::*;#()(
    // input   fd_interface_t      fd_interface_i,
    input   logic [31:0]    instr_i,
    input   logic [31:0]    pc_i,
    input   priv_e          priv_i,

    // // Decoded vals
    output  logic           valid_o,
    output  logic [4:0]     rs1_sel_o,
    output  logic [4:0]     rs2_sel_o,
    output  logic [4:0]     rd_sel_o,
    output  logic [31:0]    immediate_o,
    output  logic           use_pc_o,
    output  logic           use_imm_o,
    output  op_type_e       op_type_o,
    output  priv_op_e       priv_op_o,
    output  logic [2:0]     funct3_o,
    output  logic           arith_sub_o,

    output  logic [11:0]    csr_addr_o,
    output  logic [31:0]    csr_uimm_o
    // output  de_interface_t      de_interface_o
);
    logic [6:0] opcode, funct7;
    logic [4:0] rs1_idx, rs2_idx, rd_idx, shamt;
    logic [2:0] funct3;
    logic [31:0] imm_u, imm_j, imm_i, imm_s, imm_b;

    assign opcode       = instr_i[6:0];
    assign rs1_idx      = instr_i[19:15];
    assign rs2_idx      = instr_i[24:20];
    assign rd_idx       = instr_i[11:7];
    assign funct3       = instr_i[14:12];
    assign funct7       = instr_i[31:25];
    assign shamt        = instr_i[24:20];
    assign funct3_o     = instr_i[14:12];
    assign csr_addr_o   = instr_i[31:20];

    assign imm_u  = {instr_i[31:12], {12{1'b0}}};
    assign imm_j  = {{12{instr_i[31]}}, instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
    assign imm_i  = {{21{instr_i[31]}}, instr_i[30:20]};
    assign imm_s  = {{21{instr_i[31]}}, instr_i[30:25], instr_i[11:7]};
    assign imm_b  = {{20{instr_i[31]}}, instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
    assign csr_uimm_o   = {{27{1'b0}}, instr_i[19:15]};


    assign arith_sub_o = instr_i[30];
    // Immediate assignment
    always_comb begin
        case(opcode_e'(opcode))
            OPCODE_JALR, OPCODE_LOAD, OPCODE_ALUIMM:
                immediate_o = imm_i;
            OPCODE_STORE:
                immediate_o = imm_s;
            OPCODE_BRANCH:
                immediate_o = imm_b;
            OPCODE_LUI, OPCODE_AUIPC:
                immediate_o = imm_u;
            OPCODE_JAL:
                immediate_o = imm_j;
            default:
                immediate_o = 0;
        endcase

    end

    // OP and valid assignment
    always_comb begin
        valid_o = 1'b1;
        op_type_o = OP_ALU;
        priv_op_o = PRIVOP_ECALL;

        case(opcode_e'(opcode))
            OPCODE_LUI, OPCODE_AUIPC: begin
                op_type_o = OP_LUI_AUIPC;
            end
            OPCODE_JAL, OPCODE_JALR: begin
                op_type_o = OP_JUMP;
                // if(funct3 != 0)
                //     valid_o = 0;
            end
            OPCODE_BRANCH: begin
                op_type_o = OP_BRANCH;
                // if(cmp_op_e'(funct3) == CMP_RSV0 || cmp_op_e'(funct3) == CMP_RSV1)
                //     valid_o = 0;
            end
            OPCODE_LOAD: begin
                op_type_o = OP_LOAD;
                // if(mem_op_e'(funct3) == MEM_RSV0 || mem_op_e'(funct3) == MEM_RSV1 || mem_op_e'(funct3) == MEM_RSV2)
                    // valid_o = 0;
            end
            OPCODE_STORE: begin
                op_type_o = OP_STORE;
                // if(mem_op_e'(funct3) != MEM_8 && mem_op_e'(funct3) != MEM_16 && mem_op_e'(funct3) != MEM_32)
                    // valid_o = 0;
            end
            OPCODE_ALUIMM: begin
                op_type_o = OP_ALU;
            end
            OPCODE_ALUREG: begin
                op_type_o = OP_ALU;
                valid_o = ~(instr_i[31] | |instr_i[29:25]);
            end
            OPCODE_FENCE: begin
                op_type_o = OP_FENCE;
                // if(fence_op_e'(funct3) != FENCE && fence_op_e'(funct3) != FENCE_I)
                //     valid = 0;
            end
            OPCODE_SYSTEM: begin
                case(sys_op_e'(funct3))
                    SYS_PRIV: begin
                        case(funct7)
                            `FUNCT7_ECALL_EBREAK: begin
                                op_type_o = OP_SYSTEM;
                                priv_op_o = instr_i[20] ? PRIVOP_EBREAK : PRIVOP_ECALL;
                            end
                            `FUNCT7_SRET_WFI: begin
                                if(rs2_idx == 5'b00010 && priv_i == PRIV_SUPERVISOR) begin
                                    op_type_o = OP_SYSTEM;
                                    priv_op_o = PRIVOP_SRET;
                                end
                                else
                                    op_type_o = OP_FENCE;
                            end
                            `FUNCT7_MRET:
                                if(priv_i == PRIV_MACHINE) begin
                                    op_type_o = OP_SYSTEM;
                                    priv_op_o = PRIVOP_MRET;
                                end
                            `FUNCT7_SFENCE_VMA:
                                op_type_o = OP_FENCE;
                            `FUNCT7_SINVAL_VMA:
                                op_type_o = OP_FENCE;
                            `FUNCT7_SFENCE_INVAL:
                                op_type_o = OP_FENCE;
                            default: begin
                            end
                        endcase
                    end
                    SYS_CSRRW, SYS_CSRRWI, SYS_CSRRS, SYS_CSRRSI, SYS_CSRRC, SYS_CSRRCI: begin
                        op_type_o = OP_SYSTEM;
                    end
                    SYS_RSV0:
                        valid_o = 0;
                endcase
            end
            default:
                valid_o = 1'b0;
        endcase
    end

    // Logic assignment
    always_comb begin
        rs1_sel_o = rs1_idx;
        rs2_sel_o = rs2_idx;
        rd_sel_o = rd_idx;
        use_pc_o = 0;
        use_imm_o = 0;

        case(opcode_e'(opcode))
            OPCODE_LUI: begin
                rs1_sel_o = 0;
                use_imm_o = 1;
            end
            OPCODE_AUIPC, OPCODE_JAL, OPCODE_BRANCH: begin
                use_pc_o = 1;
                use_imm_o = 1;
            end
            OPCODE_ALUIMM, OPCODE_JALR, OPCODE_LOAD, OPCODE_STORE:
                use_imm_o = 1;
            OPCODE_ALUREG: begin
            end
            OPCODE_FENCE: begin
            end
            OPCODE_SYSTEM: begin
            end
            default: begin
            end
        endcase
    end
endmodule
