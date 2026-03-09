// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Naveen Chavali

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
    logic [31:0] enable0;
    logic [31:0] enable1;
    // logic [31:0] claim0_complete;
    // logic [31:0] claim1_complete;
    logic [31:0] claimed;           // Internal use

    logic [4:0]  irq_id0, irq_id1;
    always_comb begin
        irq_id0 = 5'b0;
        irq_id1 = 5'b0;

        for (int i = 31; i >= 0; i--) begin
            if (enable0[i] & pending[i])
                irq_id0 = i[4:0];
            if (enable1[i] & pending[i])
                irq_id1 = i[4:0];
        end
    end

    assign mei_o = (irq_id0 != 5'b0);
    assign sei_o = (irq_id1 != 5'b0);

    assign req_ready_o = 1'b1;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            pending <= 32'b0;
            enable0 <= 32'b0;
            enable1 <= 32'b0;
            claimed <= 32'b0;

            resp_valid_o <= 1'b0;
            resp_value_o <= 32'b0;
        end else begin
            pending <= {irqs_i[31:1] & ~claimed[31:1], 1'b0};
            resp_valid_o <= 1'b0;
            resp_value_o <= 32'h0;
            if (req_valid_i && (req_wstrb_i == 4'b1111 || req_wstrb_i == 4'b0000))
                resp_valid_o <= 1;

            if (req_valid_i) begin
                if (req_wstrb_i == 4'b0000) begin
                    // Prio
                    if (req_addr_i[23:7] == 17'h0)
                        resp_value_o <= 32'b1;
                    // Pending
                    if (req_addr_i[23:2] == 22'h400)
                        resp_value_o <= pending;
                    // Enable0
                    if (req_addr_i[23:2] == 22'h800)
                        resp_value_o <= enable0;
                    // Enable1
                    if (req_addr_i[23:2] == 22'h820)
                        resp_value_o <= enable1;
                    // Prio0 thresh
                    if (req_addr_i[23:2] == 22'h80000)
                        resp_value_o <= 32'b0;
                    // Prio1 thresh
                    if (req_addr_i[23:2] == 22'h80400)
                        resp_value_o <= 32'b0;

                    // claim0 complete
                    if (req_addr_i[23:2] == 22'h80001) begin
                        resp_value_o <= {27'b0, irq_id0};
                        claimed[irq_id0] <= 1'b1;
                    end
                    // claim1 complete
                    if (req_addr_i[23:2] == 22'h80401) begin
                        resp_value_o <= {27'b0, irq_id1};
                        claimed[irq_id1] <= 1'b1;
                    end
                end
                else begin
                    // Pending
                    if (req_addr_i[23:2] == 22'h400)
                        pending <= {req_value_i[31:1], 1'b0};
                    // Enable0
                    if (req_addr_i[23:2] == 22'h800)
                        enable0 <= req_value_i;
                    // Enable1
                    if (req_addr_i[23:2] == 22'h820)
                        enable1 <= req_value_i;

                    // claim0 complete
                    if (req_addr_i[23:2] == 22'h80001) begin
                        claimed[req_value_i[4:0]] <= 1'b0;
                    end
                    // claim1 complete
                    if (req_addr_i[23:2] == 22'h80401) begin
                        claimed[req_value_i[4:0]] <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
