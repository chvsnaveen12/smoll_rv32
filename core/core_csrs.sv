`timescale 1ns/1ps
module core_csrs import core_defs::*;#()(
    // Global signals
    input   logic       clk_i,
    input   logic       rst_ni,

    // Read interface
    input   logic [11:0]    raddr_i,
    output  logic [31:0]    rdata_o,
    output  logic           rvalid_o,

    // Write interface
    input   logic [11:0]    waddr_i,
    input   logic [31:0]    wdata_i,

    // Trap interface
    input   logic           exception_i,
    input   logic [31:0]    exception_code_i,
    input   logic [31:0]    exception_tval_i,
    input   logic [31:0]    instr_pc_i,
    // Trap returns
    input   logic           mret_i,
    input   logic           sret_i,

    // Interrupt interface
    output  logic           int_bool_o,
    input   logic           int_take_i,

    // Pending interrupts
    input   logic           m_ext_irq_i,
    input   logic           m_timer_irq_i,
    input   logic           m_soft_irq_i,
    input   logic           s_ext_irq_i,

    // Outputs
    output  logic [31:0]    satp_o,
    output  logic           mxr_o,
    output  logic           sum_o,
    output  logic           mprv_o,
    output  priv_e          priv_o,

    // Trap PC
    output  logic [31:0]    updated_pc_o
);
    // Current privilege level
    priv_e priv_q, priv_d;
    assign priv_o = priv_q;

    // CSR validity checks
    logic csr_priv_valid, csr_read_valid;
    assign rvalid_o = csr_priv_valid & csr_read_valid;

    // CSR registers with proper reset values
    logic [31:0] xstatus_q, xstatus_d;
    logic [31:0] medeleg_q, medeleg_d;
    logic [31:0] mideleg_q, mideleg_d;
    logic [31:0] mie_q, mie_d;
    logic [31:0] mtvec_q, mtvec_d;
    logic [31:0] mscratch_q, mscratch_d;
    logic [31:0] mepc_q, mepc_d;
    logic [31:0] mcause_q, mcause_d;
    logic [31:0] mtval_q, mtval_d;
    logic [31:0] mip_q, mip_d;
    logic [31:0] stvec_q, stvec_d;
    logic [31:0] sscratch_q, sscratch_d;
    logic [31:0] sepc_q, sepc_d;
    logic [31:0] scause_q, scause_d;
    logic [31:0] stval_q, stval_d;
    logic [31:0] satp_q, satp_d;

    // Interrupt scenes
    logic meip_valid_d;
    logic mtip_valid_d;
    logic msip_valid_d;
    logic seip_valid_d;
    logic stip_valid_d;
    logic ssip_valid_d;

    logic machine_int_enabled;
    logic supervisor_int_enabled;

    logic int_valid;
    logic int_delegated;
    logic [31:0] int_code;

    always_comb begin
        case(priv_q)
            PRIV_MACHINE:
                machine_int_enabled = xstatus_q[`CSR_MSTATUS_MIE_BIT];
            default:
                machine_int_enabled = 1'b1;
        endcase
    end

    always_comb begin
        case(priv_q)
            PRIV_MACHINE:
                supervisor_int_enabled = 1'b0;
            PRIV_SUPERVISOR:
                supervisor_int_enabled = xstatus_q[`CSR_MSTATUS_SIE_BIT];
            default:
                supervisor_int_enabled = 1'b1;
        endcase
    end

    assign meip_valid_d = mip_q[`CSR_MEIP_BIT] & machine_int_enabled;
    assign mtip_valid_d = mip_q[`CSR_MTIP_BIT] & machine_int_enabled;
    assign msip_valid_d = mip_q[`CSR_MSIP_BIT] & machine_int_enabled;
    assign seip_valid_d = mip_q[`CSR_SEIP_BIT] & (mideleg_q[`CSR_SEIP_BIT] ? supervisor_int_enabled : machine_int_enabled);
    assign stip_valid_d = mip_q[`CSR_STIP_BIT] & (mideleg_q[`CSR_STIP_BIT] ? supervisor_int_enabled : machine_int_enabled);
    assign ssip_valid_d = mip_q[`CSR_SSIP_BIT] & (mideleg_q[`CSR_SSIP_BIT] ? supervisor_int_enabled : machine_int_enabled);

    assign int_bool_o = meip_valid_d || mtip_valid_d || msip_valid_d || seip_valid_d || stip_valid_d || ssip_valid_d;

    always_comb begin
        int_code = 0;
        int_delegated = 1'b0;
        if(meip_valid_d) begin
            int_code        = (32'h80000000) | `CSR_MEIP_CODE;
        end
        else if(mtip_valid_d) begin
            int_code        = (32'h80000000) | `CSR_MTIP_CODE;
        end
        else if(msip_valid_d) begin
            int_code        = (32'h80000000) | `CSR_MSIP_CODE;
        end
        if(seip_valid_d) begin
            int_code        = (32'h80000000) | `CSR_SEIP_CODE;
            int_delegated   = mideleg_q[`CSR_SEIP_BIT];
        end
        else if(stip_valid_d) begin
            int_code    = (32'h80000000) | `CSR_STIP_CODE;
            int_delegated   = mideleg_q[`CSR_STIP_BIT];
        end
        else if(ssip_valid_d) begin
            int_code    = (32'h80000000) | `CSR_SSIP_CODE;
            int_delegated   = mideleg_q[`CSR_SSIP_BIT];
        end
    end

    // Trap Delegation
    logic trap_delegated;
    assign trap_delegated = priv_q != PRIV_MACHINE && (medeleg_q[exception_code_i[4:0]]);

    //  Update and writeback scenes
    always_comb begin
        priv_d = priv_q;
        xstatus_d = xstatus_q;
        medeleg_d = medeleg_q;
        mideleg_d = mideleg_q;
        mie_d = mie_q;
        mtvec_d = mtvec_q;
        mscratch_d = mscratch_q;
        mepc_d = mepc_q;
        mcause_d = mcause_q;
        mtval_d = mtval_q;
        mip_d = mip_q;
        stvec_d = stvec_q;
        sscratch_d = sscratch_q;
        sepc_d = sepc_q;
        scause_d = scause_q;
        stval_d = stval_q;
        satp_d = satp_q;

        updated_pc_o = 0;

        mip_d[`CSR_MEIP_BIT]        = m_ext_irq_i;
        mip_d[`CSR_MTIP_BIT]        = m_timer_irq_i;
        mip_d[`CSR_MSIP_BIT]        = m_soft_irq_i;
        mip_d[`CSR_SEIP_BIT]        = s_ext_irq_i;

        if(exception_i && !trap_delegated || int_take_i && !int_delegated) begin
            mepc_d                          = instr_pc_i;
            mcause_d                        = exception_i ? exception_code_i : int_code;
            mtval_d                         = exception_tval_i;

            xstatus_d[`CSR_MSTATUS_MPP_BIT+:2]  = 2'(priv_q);
            xstatus_d[`CSR_MSTATUS_MIE_BIT]     = 1'b0;
            xstatus_d[`CSR_MSTATUS_MPIE_BIT]    = xstatus_q[`CSR_MSTATUS_MIE_BIT];
            priv_d                              = PRIV_MACHINE;

            updated_pc_o                        = mtvec_q;
        end
        else if(exception_i && trap_delegated || int_take_i && int_delegated) begin
            sepc_d                          = instr_pc_i;
            scause_d                        = exception_i ? exception_code_i : int_code;
            stval_d                         = exception_tval_i;

            xstatus_d[`CSR_MSTATUS_SPP_BIT]     = priv_q[0];
            xstatus_d[`CSR_MSTATUS_SIE_BIT]     = 1'b0;
            xstatus_d[`CSR_MSTATUS_SPIE_BIT]    = xstatus_q[`CSR_MSTATUS_SIE_BIT];
            priv_d                              = PRIV_SUPERVISOR;

            updated_pc_o                        = stvec_q;

        end
        else if(mret_i) begin
            xstatus_d[`CSR_MSTATUS_MIE_BIT]     = xstatus_q[`CSR_MSTATUS_MPIE_BIT];
            xstatus_d[`CSR_MSTATUS_MPIE_BIT]    = 1'b1;
            priv_d                              = priv_e'(xstatus_q[`CSR_MSTATUS_MPP_BIT+:2]);
            xstatus_d[`CSR_MSTATUS_MPP_BIT+:2]  = 2'(PRIV_USER);
            xstatus_d[`CSR_MSTATUS_MPRV_BIT]    = priv_d == PRIV_MACHINE ? xstatus_q[`CSR_MSTATUS_MPRV_BIT] : 0;
            updated_pc_o                        = mepc_q;
        end

        else if(sret_i) begin
            xstatus_d[`CSR_MSTATUS_SIE_BIT]     = xstatus_q[`CSR_MSTATUS_SPIE_BIT];
            xstatus_d[`CSR_MSTATUS_SPIE_BIT]    = 1'b1;
            priv_d                              = priv_e'({1'b0, xstatus_q[`CSR_MSTATUS_SPP_BIT]});
            xstatus_d[`CSR_MSTATUS_SPP_BIT]     = 1'b0;
            updated_pc_o                        = sepc_q;
        end

        else if(waddr_i != 0) begin
            case(waddr_i)
                `CSR_M_STATUS_ADDR:
                    xstatus_d       = (xstatus_q & ~`CSR_MSTATUS_MASK) | (wdata_i & `CSR_MSTATUS_MASK);
                `CSR_M_EDELEG_ADDR:
                    medeleg_d       = wdata_i & `CSR_MEDELEG_MASK;
                `CSR_M_IDELEG_ADDR:
                    mideleg_d       = wdata_i & `CSR_SIE_SIP_MASK;
                `CSR_M_IE_ADDR:
                    mie_d           = wdata_i & `CSR_MIE_MIP_MASK;
                `CSR_M_TVEC_ADDR:
                    mtvec_d         = wdata_i & `CSR_TVEC_MASK;
                `CSR_M_SCRATCH_ADDR:
                    mscratch_d      = wdata_i;
                `CSR_M_EPC_ADDR:
                    mepc_d          = wdata_i & `CSR_EPC_MASK;
                `CSR_M_CAUSE_ADDR:
                    mcause_d        = wdata_i;
                `CSR_M_TVAL_ADDR:
                    mtval_d         = wdata_i;
                `CSR_M_IP_ADDR:
                    mip_d           = (mip_q & ~`CSR_SIE_SIP_MASK) | (wdata_i & `CSR_SIE_SIP_MASK);

                `CSR_S_STATUS_ADDR:
                    xstatus_d       = (xstatus_q & ~`CSR_SSTATUS_MASK) | (wdata_i & `CSR_SSTATUS_MASK);
                `CSR_S_IE_ADDR:
                    mie_d           = (mie_q & ~`CSR_SIE_SIP_MASK) | (wdata_i & `CSR_SIE_SIP_MASK);
                `CSR_S_TVEC_ADDR:
                    stvec_d         = wdata_i & `CSR_TVEC_MASK;
                `CSR_S_SCRATCH_ADDR:
                    sscratch_d      = wdata_i;
                `CSR_S_EPC_ADDR:
                    sepc_d          = wdata_i & `CSR_EPC_MASK;
                `CSR_S_CAUSE_ADDR:
                    scause_d        = wdata_i;
                `CSR_S_TVAL_ADDR:
                    stval_d         = wdata_i;
                `CSR_S_IP_ADDR:
                    mip_d           = (mip_q & ~`CSR_SIP_SSIP_MASK) | (wdata_i & `CSR_SIP_SSIP_MASK);
                `CSR_S_ATP_ADDR:
                    satp_d          = wdata_i == 0 || wdata_i[`CSR_SATP_MODE_BIT] == 1 ? wdata_i : satp_q;
                default: begin
                end
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rst_ni) begin
            priv_q          <= PRIV_MACHINE;
            xstatus_q       <= 32'h0;
            medeleg_q       <= 32'h0;
            mideleg_q       <= 32'h0;
            mie_q           <= 32'h0;
            mtvec_q         <= 32'h0;
            mscratch_q      <= 32'h0;
            mepc_q          <= 32'h0;
            mcause_q        <= 32'h0;
            mtval_q         <= 32'h0;
            mip_q           <= 32'h0;
            stvec_q         <= 32'h0;
            sscratch_q      <= 32'h0;
            sepc_q          <= 32'h0;
            scause_q        <= 32'h0;
            stval_q         <= 32'h0;
            satp_q          <= 32'h0;

        end
        else begin
            priv_q          <= priv_d;
            xstatus_q       <= xstatus_d;
            medeleg_q       <= medeleg_d;
            mideleg_q       <= mideleg_d;
            mie_q           <= mie_d;
            mtvec_q         <= mtvec_d;
            mscratch_q      <= mscratch_d;
            mepc_q          <= mepc_d;
            mcause_q        <= mcause_d;
            mtval_q         <= mtval_d;
            mip_q           <= mip_d;
            stvec_q         <= stvec_d;
            sscratch_q      <= sscratch_d;
            sepc_q          <= sepc_d;
            scause_q        <= scause_d;
            stval_q         <= stval_d;
            satp_q          <= satp_d;
        end
    end

    //  CSR reads
    always_comb begin
        rdata_o = 0;
        csr_read_valid = 1'b1;
        csr_priv_valid = 1'b1;

        if(priv_e'(raddr_i[`CSR_PRIV_BIT+1:`CSR_PRIV_BIT]) == PRIV_MACHINE && priv_q != PRIV_MACHINE)
            csr_priv_valid = 1'b0;
        
        else if(priv_e'(raddr_i[`CSR_PRIV_BIT+1:`CSR_PRIV_BIT]) == PRIV_SUPERVISOR && priv_q != PRIV_MACHINE && priv_q != PRIV_SUPERVISOR)
            csr_priv_valid = 1'b0;

        case(raddr_i)
            `CSR_M_HARTID_ADDR:
                rdata_o = 32'h0;
            `CSR_M_VENDORID_ADDR, `CSR_M_IMPID_ADDR, `CSR_M_ARCHID_ADDR:
                rdata_o = 0;
            
            `CSR_M_STATUS_ADDR:
                rdata_o = xstatus_q & `CSR_MSTATUS_MASK;
            `CSR_M_STATUSH_ADDR:
                rdata_o = 0;
            `CSR_M_ISA_ADDR:
                rdata_o = `CSR_MISA_DEFAULT;
            `CSR_M_EDELEG_ADDR:
                rdata_o = medeleg_q;
            `CSR_M_IDELEG_ADDR:
                rdata_o = mideleg_q;
            `CSR_M_IE_ADDR:
                rdata_o = mie_q;
            `CSR_M_TVEC_ADDR:
                rdata_o = mtvec_q;
            `CSR_M_SCRATCH_ADDR:
                rdata_o = mscratch_q;
            `CSR_M_EPC_ADDR:
                rdata_o = mepc_q;
            `CSR_M_CAUSE_ADDR:
                rdata_o = mcause_q;
            `CSR_M_TVAL_ADDR:
                rdata_o = mtval_q;
            `CSR_M_IP_ADDR:
                rdata_o = mip_q;
            `CSR_S_STATUS_ADDR:
                rdata_o = xstatus_q & `CSR_SSTATUS_MASK;
            `CSR_S_IE_ADDR:
                rdata_o = mie_q & mideleg_q;
            `CSR_S_TVEC_ADDR:
                rdata_o = stvec_q;
            `CSR_S_COUNTEREN_ADDR:
                rdata_o = `CSR_COUNTEREN_DEFAULT;
            `CSR_S_SCRATCH_ADDR:
                rdata_o = sscratch_q;
            `CSR_S_EPC_ADDR:
                rdata_o = sepc_q; 
            `CSR_S_CAUSE_ADDR:
                rdata_o = scause_q;
            `CSR_S_TVAL_ADDR:
                rdata_o = stval_q;
            `CSR_S_IP_ADDR:
                rdata_o = mip_q & mideleg_q;
            `CSR_S_ATP_ADDR:
                rdata_o = satp_q;
            default:
                csr_read_valid = 1'b0;
        endcase
    end
endmodule
