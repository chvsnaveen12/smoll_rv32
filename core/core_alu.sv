module core_shifter #()(
    input   logic [31:0]    inp_i,
    input   logic [4:0]     shamt_i,
    input   logic           left_shift_i,
    input   logic           shift_arith_i,
    
    output  logic [31:0]    out_o
);
    // Input to the shifter and output from the shifter
    logic [31:0] shift_inp, shift_out;
    logic [31:0] shift0, shift1, shift2, shift3, shift4;
    logic pad;

    assign pad = shift_arith_i ? inp_i[31] : 0;

    // Flip the input if it's a left shift
    always_comb begin
        if(left_shift_i)
            for(int i = 0; i < 32; i++)
                shift_inp[31-i] = inp_i[i];
        else
            shift_inp = inp_i;
    end

    // Barrel right shifter
    assign shift0 = shamt_i[0] ? {{1{pad}},  shift_inp[31:1]} : shift_inp;
    assign shift1 = shamt_i[1] ? {{2{pad}},  shift0[31:2]} : shift0;
    assign shift2 = shamt_i[2] ? {{4{pad}},  shift1[31:4]} : shift1;
    assign shift3 = shamt_i[3] ? {{8{pad}},  shift2[31:8]} : shift2;
    assign shift4 = shamt_i[4] ? {{16{pad}}, shift3[31:16]} : shift3;

    // Flip the input if it's a left shift
    always_comb begin
        if(left_shift_i)
            for(int i = 0; i < 32; i++)
                shift_out[31-i] = shift4[i];
        else
            shift_out = shift4;
    end

    assign out_o = shift_out;
endmodule

module core_comparator #()(
    input logic [31:0]      operand_a_i,
    input logic [31:0]      operand_b_i,

    output logic            eq_flag_o,
    output logic            lt_flag_o,
    output logic            ltu_flag_o
);
    logic [31:0] difference;

    assign difference = operand_a_i - operand_b_i;

    assign eq_flag_o = difference == 0 ? 1 : 0;
    assign lt_flag_o = operand_a_i[31] == operand_b_i[31] ? difference[31] : operand_a_i[31];
    assign ltu_flag_o = operand_a_i[31] == operand_b_i[31] ? difference[31] : operand_b_i[31];
endmodule

module core_alu import core_defs::*;#()(
    input   logic [31:0]    rs1_i,
    input   logic [31:0]    rs2_i,
    input   logic [31:0]    immediate_i,
    input   logic [31:0]    pc_i,
    input   logic           use_pc_i,
    input   logic           use_imm_i,
    input   logic           arith_sub_i,
    input   logic [2:0]     funct3_i,

    input   logic [31:0]    csr_rdata_i,
    input   logic [31:0]    csr_uimm_i,

    output  logic [31:0]    output_o,
    output  logic [31:0]    sum_o,
    output  logic           branch_flag_o,

    output  logic [31:0]    csr_wdata_o
);
    logic [31:0] operand_a, operand_b, diff, shift, csr_inp;
    logic [4:0] shamt;
    logic lshift;
    logic eq_flag, lt_flag, ltu_flag, branch_pre_neg;
    
    assign operand_a        = use_pc_i ? pc_i : rs1_i;
    assign operand_b        = use_imm_i ? immediate_i : rs2_i;
    assign shamt            = use_imm_i ? immediate_i[4:0] : rs2_i[4:0];

    assign sum_o            = operand_a + operand_b;
    assign diff             = operand_a - operand_b;

    core_shifter shifter(
        .inp_i(operand_a),
        .shamt_i(shamt),
        .left_shift_i(lshift),
        .shift_arith_i(arith_sub_i),

        .out_o(shift)
    );

    core_comparator comparator(
        .operand_a_i(rs1_i),
        .operand_b_i(rs2_i),
        
        .eq_flag_o(eq_flag),
        .lt_flag_o(lt_flag),
        .ltu_flag_o(ltu_flag)
    );

    always_comb begin
        lshift = 0;
        case(alu_op_e'(funct3_i))
            ALU_ADD: begin
                output_o = arith_sub_i & !use_imm_i ? diff : sum_o;
            end
            ALU_SLL: begin
                lshift = 1;
                output_o = shift;
            end
            ALU_SLT:
                output_o = {{31{1'b0}}, operand_a[31] == operand_b[31] ? diff[31] : operand_a[31]};
            ALU_SLTU:
                output_o = {{31{1'b0}}, operand_a[31] == operand_b[31] ? diff[31] : operand_b[31]};
            ALU_XOR:
                output_o = operand_a ^ operand_b;
            ALU_SRL_SRA:
                output_o = shift;
            ALU_OR:
                output_o = operand_a | operand_b;
            ALU_AND:
                output_o = operand_a & operand_b;
        endcase
    end

    always_comb begin
        case(cmp_op_e'({funct3_i[2:1], 1'b0}))
            CMP_EQ:
                branch_pre_neg = eq_flag;
            CMP_LT:
                branch_pre_neg = lt_flag;
            CMP_LTU:
                branch_pre_neg = ltu_flag;
            default:
                branch_pre_neg = 0;
        endcase
    end
    assign branch_flag_o = funct3_i[0] ? !branch_pre_neg : branch_pre_neg;


    assign csr_inp = funct3_i[2] ? csr_uimm_i : rs1_i;

    always_comb begin
        case(sys_op_e'({1'b0, funct3_i[1:0]}))
            SYS_CSRRW:
                csr_wdata_o = rs1_i;
            SYS_CSRRS:
                csr_wdata_o = csr_rdata_i | csr_inp;
            SYS_CSRRC:
                csr_wdata_o = csr_rdata_i & ~csr_inp;
            default:
                csr_wdata_o = 0;
        endcase
    end

endmodule
