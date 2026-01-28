module core_regs #()(
    input   logic   clk_i,
    input   logic   rst_ni,

    input   logic [4:0]     raddr_a_i,
    input   logic [4:0]     raddr_b_i,
    input   logic [4:0]     waddr_i,
    input   logic [31:0]    wdata_i,

    output  logic [31:0]    rdata_a_o,
    output  logic [31:0]    rdata_b_o
);

    logic [31:0] registers [0:31];

    always_comb begin
        rdata_a_o = raddr_a_i != 0 ? registers[raddr_a_i] : 0;
        rdata_b_o = raddr_b_i != 0 ? registers[raddr_b_i] : 0;
    end

    always_ff @(posedge clk_i) begin
        if(waddr_i != 0)
            registers[waddr_i] <=  wdata_i;
    end

endmodule
