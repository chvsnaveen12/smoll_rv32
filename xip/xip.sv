module flash_controller (
    input   logic           clk_i,
    input   logic           rst_ni,

    input   logic           req_valid_i,
    input   logic [31:0]    req_addr_i,
    input   logic [31:0]    req_value_i,
    input   logic           req_wstrb_i,
    output  logic           req_ready_o,

    output  logic           resp_valid_o,
    output  logic [31:0]    resp_value_o,

    output  logic           cs_no,
    output  logic           sck_o,
    output  logic           mosi_o,
    input   logic           miso_i
);
    typedef enum logic [1:0] {
        STATE_IDLE             = 2'b00,
        STATE_REFILL           = 2'b01,
        STATE_FINISH           = 2'b10
    } state_e;
    state_e state_q;

    logic [7:0]     spi_count;
    logic [31:0]    shift_buffer;
    
    // Div/4 clock logic
    logic [1:0]     clk_div_cnt;
    logic           spi_clk_q;
    logic           spi_tick;  // Pulses once per SPI clock cycle (on rising edge of spi_clk)
    
    // spi_tick pulses when clk_div_cnt transitions from 1 to 2 (rising edge of spi_clk)
    assign spi_tick = (state_q == STATE_REFILL) && (clk_div_cnt == 2'b01);
    
    assign sck_o = spi_clk_q;

    // Unified posedge block - handles clock division, FSM, and MOSI
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            clk_div_cnt <= 2'b00;
            spi_clk_q <= 1'b0;
            state_q <= STATE_IDLE;
            req_ready_o <= 1'b0;
            resp_valid_o <= 1'b0;
            spi_count <= 8'b0;
            cs_no <= 1'b1;
            resp_value_o <= 32'b0;
            shift_buffer <= 32'b0;
            mosi_o <= 1'b0;
        end else begin
            resp_valid_o <= 1'b0;
            
            // Clock divider logic
            if (state_q == STATE_REFILL) begin
                clk_div_cnt <= clk_div_cnt + 1;
                // Toggle spi_clk every 2 input clock cycles
                if (clk_div_cnt == 2'b01)
                    spi_clk_q <= 1'b1;
                else if (clk_div_cnt == 2'b11)
                    spi_clk_q <= 1'b0;
            end else begin
                clk_div_cnt <= 2'b00;
                spi_clk_q <= 1'b0;
            end
            
            case(state_q)
                STATE_IDLE: begin
                    req_ready_o <= 1'b1;
                    cs_no <= 1'b1;
                    spi_count <= 8'b0;
                    mosi_o <= 1'b0;
                    if(req_valid_i) begin
                        req_ready_o <= 1'b0;
                        state_q <= STATE_REFILL;
                        shift_buffer <= {8'h03, req_addr_i[23:0]};
                        cs_no <= 1'b0;
                        // Pre-load first MOSI bit
                        mosi_o <= 1'b0; // Will be updated on first falling edge
                    end
                end

                STATE_REFILL: begin
                    req_ready_o <= 1'b0;
                    
                    // Update MOSI on falling edge of SPI clock (clk_div_cnt == 3)
                    if (clk_div_cnt == 2'b11) begin
                        if(spi_count < 32)
                            mosi_o <= shift_buffer[31];
                        else
                            mosi_o <= 1'b0;
                    end
                    
                    // Advance SPI state on rising edge of divided clock
                    if (spi_tick) begin
                        spi_count <= spi_count + 1;
                        shift_buffer <= {shift_buffer[30:0], miso_i};
                        
                        if(spi_count == 63) begin
                            state_q <= STATE_FINISH;
                            resp_value_o <= {shift_buffer[6:0], miso_i, shift_buffer[14:7], shift_buffer[22:15], shift_buffer[30:23]};
                        end
                    end
                end

                STATE_FINISH: begin
                    cs_no <= 1'b1;
                    state_q <= STATE_IDLE;
                    resp_valid_o <= 1'b1;
                    req_ready_o <= 1'b1;
                    mosi_o <= 1'b0;
                end
                default: begin
                    state_q <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

