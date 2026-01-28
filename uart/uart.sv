module uart(
    input  logic clk_i,
    input  logic rst_ni,

    // Bus interface
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_value_i,
    input  logic [3:0]  req_wstrb_i,
    input  logic        req_valid_i,
    output logic        req_ready_o,

    output logic [31:0] resp_value_o,
    output logic resp_valid_o,

    output logic uart_rx_irq_o,

    input logic rx_i,
    output logic tx_o
);

    // RX loop
    logic sync0, sync1;
    logic rx_synced;

    assign rx_synced = sync1;

    always_ff @(posedge clk_i) begin
        sync0 <= rx_i;
        sync1 <= sync0;
    end

    logic rx_busy;
    logic [31:0] rx_cnt;
    logic [3:0] rx_bit_cnt;
    logic [9:0] rx_data;
    logic [7:0] rx_latch;
    logic [31:0] div;
    // logic uart_rx_irq_o;

    // Internal signals for bus-logic interaction
    logic rx_irq_clr;
    logic tx_start;
    logic [7:0] tx_byte;

    // RX loop
    always_ff @(posedge clk_i) begin
        if(!rst_ni) begin
            rx_busy <= 0;
            rx_cnt <= 0;
            rx_bit_cnt <= 0;
            rx_data <= 0;
            div <= 32'd650;
            uart_rx_irq_o <= 0;
        end
        else begin
            if (rx_irq_clr) begin
                uart_rx_irq_o <= 0;
            end

            // if(!rx_synced && !rx_busy) begin
            if(!rx_busy) begin
                if(!rx_i) begin
                    rx_busy <= 1;
                    rx_cnt <= div >> 1;
                    rx_bit_cnt <= 0;
                end
            end
            else begin
                if(rx_cnt == 0) begin
                    rx_cnt <= div;
                    rx_bit_cnt <= rx_bit_cnt + 1;
                    rx_data <= rx_data << 1;
                    // rx_data[0] <= rx_synced;
                    rx_data[0] <= rx_i;
                    if(rx_bit_cnt == 9) begin
                        uart_rx_irq_o <= 1;
                        rx_latch <= rx_data[7:0];
                        rx_busy <= 0;
                    end
                end
                else begin
                    rx_cnt <= rx_cnt - 1;
                end
            end
        end
    end

    // TX loop
    logic [31:0] tx_cnt;
    logic [3:0] tx_bit_cnt;
    logic [10:0] tx_data;
    logic tx_send;

    always_ff @(posedge clk_i) begin
        if(!rst_ni) begin
            tx_o <= 1'b1;
            tx_cnt <= 0;
            tx_bit_cnt <= 0;
            tx_send <= 0;
            tx_data <= 0;
        end
        else begin
            if (tx_start && !tx_send) begin
                tx_data <= {2'b11, tx_byte, 1'b0};
                tx_send <= 1;
                tx_cnt <= div;
                tx_bit_cnt <= 0;
            end
            else if(tx_send) begin
                tx_cnt <= tx_cnt - 1;
                if(tx_cnt == 0) begin
                    tx_o <= tx_data[0];
                    tx_data <= tx_data >> 1;
                    tx_cnt <= div;
                    tx_bit_cnt <= tx_bit_cnt + 1;
                    if(tx_bit_cnt == 10) begin
                        tx_send <= 0;
                        tx_bit_cnt <= 0;
                    end
                end
            end
        end
    end

    // Read write from mem
    assign req_ready_o = 1'b1;
    always_ff @(posedge clk_i) begin
        rx_irq_clr <= 0;
        tx_start <= 0;
        tx_byte <= 0;

        if(!rst_ni) begin
            resp_valid_o <= 1'b0;
            resp_value_o <= 32'b0;
        end else begin
            resp_valid_o <= 1'b0;
            resp_value_o <= 32'b0;
            if(req_valid_i) begin
                resp_valid_o <= 1'b1;
                if(~|req_wstrb_i) begin
                    case(req_addr_i)
                        32'h0: begin
                            resp_value_o <= {24'b0, rx_latch};
                        end
                        32'h4: begin
                            resp_value_o <= {31'b0, uart_rx_irq_o};
                            rx_irq_clr <= 1'b1;
                        end
                        32'hc8: begin
                            resp_value_o <= {24'b0, tx_data[8:1]};
                        end
                        32'hc: begin
                            resp_value_o <= {31'b0, tx_send};
                        end
                    endcase
                end
                else if(req_wstrb_i == 4'b1111) begin
                    case(req_addr_i)
                        32'h8: begin
                            tx_byte <= req_value_i[7:0];
                            tx_start <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

endmodule
