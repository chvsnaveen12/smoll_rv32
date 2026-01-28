module plic #()(
    input logic clk_i,
    input logic rst_ni,

    // Bus Interface
    input  logic        req_valid_i,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_value_i,
    input  logic [3:0]  req_wstrb_i,
    
    output logic        req_ready_o,
    output logic        resp_valid_o,
    output logic [31:0] resp_value_o,

    // Interrupts
    input  logic [31:0] irqs_i,
    output logic        mei_o,
    output logic        sei_o
);

    logic [31:0] pending;
    logic [31:0] prio [0:31];
    logic [31:0] enable0;
    logic [31:0] enable1;
    logic [31:0] prio0_threshold;
    logic [31:0] prio1_threshold;
    logic [31:0] claim0_complete;
    logic [31:0] claim1_complete;
    logic [31:0] claimed;           // Internal use

    always_ff @(posedge clk_i) begin
        if(!rst_ni) begin
            pending <= 32'b0;
            prio <= 32'b0;
            enable0 <= 32'b0;
            enable1 <= 32'b0;
            prio0_threshold <= 32'b0;
            prio1_threshold <= 32'b0;
            claim0_complete <= 32'b0;
            claim1_complete <= 32'b0;
            claimed <= 32'b0;
        end else begin
            pending <= irqs_i & ~claimed;
            
        end
    end

endmodule
