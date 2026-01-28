`timescale 1ns/1ps
package core_defs;

    typedef enum logic [2:0] {
        OP_ALU          = 3'b000,
        OP_JUMP         = 3'b001,
        OP_BRANCH       = 3'b010,
        OP_LOAD         = 3'b011,
        OP_STORE        = 3'b100,
        OP_LUI_AUIPC    = 3'b101,
        OP_FENCE        = 3'b110,
        OP_SYSTEM       = 3'b111
    } op_type_e;

    typedef enum logic [2:0] {
        CMP_EQ      = 3'b000,
        CMP_NE      = 3'b001,
        CMP_RSV0    = 3'b010,
        CMP_RSV1    = 3'b011,
        CMP_LT      = 3'b100,
        CMP_GE      = 3'b101,
        CMP_LTU     = 3'b110,
        CMP_GEU     = 3'b111
    } cmp_op_e;

    typedef enum logic [2:0] {
        ALU_ADD     = 3'b000,
        ALU_SLL     = 3'b001,
        ALU_SLT     = 3'b010,
        ALU_SLTU    = 3'b011,
        ALU_XOR     = 3'b100,
        ALU_SRL_SRA = 3'b101,
        ALU_OR      = 3'b110,
        ALU_AND     = 3'b111
    } alu_op_e;

    typedef enum logic [2:0] {
        MEM_8       = 3'b000,
        MEM_16      = 3'b001,
        MEM_32      = 3'b010,
        MEM_RSV0    = 3'b011,
        MEM_8U      = 3'b100,
        MEM_16U     = 3'b101,
        MEM_RSV1    = 3'b110,
        MEM_RSV2    = 3'b111
    } mem_op_e;

    typedef enum logic [2:0] {
        FENCE       = 3'b000,
        FENCE_I     = 3'b001,
        FENCE_RSV0  = 3'b010,
        FENCE_RSV1  = 3'b011,
        FENCE_RSV2  = 3'b100,
        FENCE_RSV3  = 3'b101,
        FENCE_RSV4  = 3'b110,
        FENCE_RSV5  = 3'b111
    } fence_op_e;

    typedef enum logic [2:0] {
        SYS_PRIV    = 3'b000,
        SYS_CSRRW   = 3'b001,
        SYS_CSRRS   = 3'b010,
        SYS_CSRRC   = 3'b011,
        SYS_RSV0    = 3'b100,
        SYS_CSRRWI  = 3'b101,
        SYS_CSRRSI  = 3'b110,
        SYS_CSRRCI  = 3'b111
    } sys_op_e;

    typedef enum logic [1:0] {
        PRIVOP_ECALL              = 2'b00,
        PRIVOP_EBREAK             = 2'b01,
        PRIVOP_SRET               = 2'b10,
        PRIVOP_MRET               = 2'b11
    } priv_op_e;

    typedef enum logic [6:0] {
        OPCODE_LUI      = 7'b0110111,
        OPCODE_AUIPC    = 7'b0010111,
        OPCODE_JAL      = 7'b1101111,
        OPCODE_JALR     = 7'b1100111,
        OPCODE_BRANCH   = 7'b1100011,
        OPCODE_LOAD     = 7'b0000011,
        OPCODE_STORE    = 7'b0100011,
        OPCODE_ALUIMM   = 7'b0010011,
        OPCODE_ALUREG   = 7'b0110011,
        OPCODE_FENCE    = 7'b0001111,
        OPCODE_SYSTEM   = 7'b1110011
    } opcode_e;

    typedef enum logic [1:0] {
        PRIV_USER           = 2'b00,
        PRIV_SUPERVISOR     = 2'b01,
        PRIV_RSV0           = 2'b10,
        PRIV_MACHINE        = 2'b11
    } priv_e;


    typedef struct packed {
        // The instruction
        logic [31:0]    instr;
        logic [31:0]    pc;

        // The pc + 4 for JAL and JALR
        logic [31:0]    npc;
    } fd_interface_t;

    typedef struct packed {
        // Is the output valid?
        logic           valid;

        // Selecting rs1, rs2 and rd from reg_file
        logic [4:0]     rs1_addr;
        logic [4:0]     rs2_addr;
        logic [4:0]     rd_addr;

        // Immediate value
        logic [31:0]    immediate;

        // Select between rs1 or pc for input_a of the ALU
        logic           use_pc;

        // Select between rs2 or imm for input_b of the ALU
        logic           use_imm;

        // Is it an ALU, LOAD, STORE, BRANCH, JUMP or SYSTEM operation
        op_type_e       op_type;

        // For a lot a of intstruions this acts as input
        // Always typecasted to cmp_type_e, alu_type_e, or mem_op_e
        logic [3:0]     funct3;
        // Required because SRL and SRA have the same encoding
        logic           shift_arithmetic;

    } de_interface_t;

    `define FUNCT7_ECALL_EBREAK     7'b0000000
    `define FUNCT7_SRET_WFI         7'b0001000
    `define FUNCT7_MRET             7'b0011000
    `define FUNCT7_SFENCE_VMA       7'b0001001
    `define FUNCT7_SINVAL_VMA       7'b0001011
    `define FUNCT7_SFENCE_INVAL     7'b0001100


    `define CSR_M_VENDORID_ADDR     12'hf11
    `define CSR_M_ARCHID_ADDR       12'hf12
    `define CSR_M_IMPID_ADDR        12'hf13
    `define CSR_M_HARTID_ADDR       12'hf14

    `define CSR_M_STATUS_ADDR       12'h300
    `define CSR_M_STATUSH_ADDR      12'h310
    `define CSR_M_ISA_ADDR          12'h301
    `define CSR_M_EDELEG_ADDR       12'h302
    `define CSR_M_IDELEG_ADDR       12'h303
    `define CSR_M_IE_ADDR           12'h304
    `define CSR_M_TVEC_ADDR         12'h305
    `define CSR_M_SCRATCH_ADDR      12'h340
    `define CSR_M_EPC_ADDR          12'h341
    `define CSR_M_CAUSE_ADDR        12'h342
    `define CSR_M_TVAL_ADDR         12'h343
    `define CSR_M_IP_ADDR           12'h344

    `define CSR_S_STATUS_ADDR       12'h100
    `define CSR_S_IE_ADDR           12'h104
    `define CSR_S_TVEC_ADDR         12'h105
    `define CSR_S_COUNTEREN_ADDR    12'h106
    `define CSR_S_SCRATCH_ADDR      12'h140
    `define CSR_S_EPC_ADDR          12'h141
    `define CSR_S_CAUSE_ADDR        12'h142
    `define CSR_S_TVAL_ADDR         12'h143
    `define CSR_S_IP_ADDR           12'h144
    `define CSR_S_ATP_ADDR          12'h180

    `define CSR_PRIV_BIT            8

    `define CSR_MSTATUS_MASK        32'h000ff9aa
    `define CSR_SSTATUS_MASK        32'h000de122
    `define CSR_MSTATUS_SIE_BIT     1
    `define CSR_MSTATUS_MIE_BIT     3
    `define CSR_MSTATUS_SPIE_BIT    5
    `define CSR_MSTATUS_MPIE_BIT    7
    `define CSR_MSTATUS_SPP_BIT     8
    `define CSR_MSTATUS_MPP_BIT     11
    `define CSR_MSTATUS_MPRV_BIT    17
    `define CSR_MSTATUS_SUM_BIT     18
    `define CSR_MSTATUS_MXR_BIT     19

    `define CSR_MEDELEG_MASK        32'h0000b3ff

    `define CSR_EPC_MASK            32'hfffffffe
    `define CSR_TVEC_MASK           32'hfffffffd

    `define CSR_SIE_SIP_MASK        32'h00000222
    `define CSR_MIE_MIP_MASK        32'h00000aaa
    `define CSR_SIP_SSIP_MASK       32'h00000002
    `define CSR_SSIP_BIT            1
    `define CSR_MSIP_BIT            3
    `define CSR_STIP_BIT            5
    `define CSR_MTIP_BIT            7
    `define CSR_SEIP_BIT            9
    `define CSR_MEIP_BIT            11

    `define CSR_SSIP_CODE           32'h1
    `define CSR_MSIP_CODE           32'h3
    `define CSR_STIP_CODE           32'h5
    `define CSR_MTIP_CODE           32'h7
    `define CSR_SEIP_CODE           32'h9
    `define CSR_MEIP_CODE           32'h11


    `define CSR_SATP_MODE_BIT       31

    `define CSR_COUNTEREN_DEFAULT   32'hffffffff
    `define CSR_MISA_DEFAULT        32'h40141101

endpackage
