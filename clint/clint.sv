module clint #(
    parameter MTIME_DIV = 4
)(
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
    output logic        msi_o,
    output logic        mti_o
);

    logic [4:0] mtime_div;
    logic [63:0] mtime;
    logic [63:0] mtimecmp;
    logic [31:0] msip;

    assign mti_o = (mtime >= mtimecmp);
    assign msi_o = msip[0];

    assign req_ready_o = 1'b1;

    always_ff @(posedge clk_i) begin
        if(!rst_ni) begin
            mtime <= 0;
            mtimecmp <= 64'hffffffffffffffff;
            msip <= 0;
            mtime_div <= 0;
        end else begin
            mtime_div <= mtime_div + 1;
            if(mtime_div == MTIME_DIV) begin
                mtime <= mtime + 1;
                mtime_div <= 0;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rst_ni) begin
            resp_valid_o <= 1'b0;
            resp_value_o <= 32'b0;
        end else begin
            resp_valid_o <= 1'b0;
            resp_value_o <= 32'h0;

            if(req_valid_i) begin
                if(~|req_wstrb_i) begin
                    case(req_addr_i)
                        32'h0: begin
                            resp_valid_o <= 1'b1;
                            resp_value_o <= msip;
                        end
                        32'h4000: begin
                            resp_valid_o <= 1'b1;
                            resp_value_o <= mtimecmp[31:0];
                        end
                        32'h4004: begin
                            resp_valid_o <= 1'b1;
                            resp_value_o <= mtimecmp[63:32];
                        end
                        32'hbff8: begin
                            resp_valid_o <= 1'b1;
                            resp_value_o <= mtime[31:0];
                        end
                        32'hbffc: begin
                            resp_valid_o <= 1'b1;
                            resp_value_o <= mtime[63:32];
                        end
                    endcase
                end
                else if(req_wstrb_i == 4'b1111) begin
                    case(req_addr_i)
                        32'h0: begin
                            resp_valid_o <= 1'b1;
                            msip <= req_value_i;
                        end
                        32'h4000: begin
                            resp_valid_o <= 1'b1;
                            mtimecmp[31:0] <= req_value_i;
                        end
                        32'h4004: begin
                            resp_valid_o <= 1'b1;
                            mtimecmp[63:32] <= req_value_i;
                        end
                        32'hbff8: begin
                            resp_valid_o <= 1'b1;
                            mtime[31:0] <= req_value_i;
                        end
                        32'hbffc: begin
                            resp_valid_o <= 1'b1;
                            mtime[63:32] <= req_value_i;
                        end
                    endcase
                end
            end

        end
    end
endmodule