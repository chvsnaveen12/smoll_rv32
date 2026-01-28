module spi (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Bus Interface
    input  logic        req_valid_i,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_value_i,
    input  logic [3:0]  req_wstrb_i,
    
    output logic        req_ready_o,
    output logic        resp_valid_o,
    output logic [31:0] resp_value_o,

    // SPI Pins
    output logic        spi_cs_n_o,
    output logic        spi_sck_o,
    output logic        spi_mosi_o,
    input  logic        spi_miso_i
);

    // ---------------------------------------------------------
    // 1. Internal Registers
    // ---------------------------------------------------------
    logic [15:0] clk_div;      // 0x0C
    logic        cs_reg;       // 0x08
    logic [7:0]  tx_shift;     // 0x00 (Write)
    logic [7:0]  rx_data;      // 0x04 (Read) - Final captured byte
    logic        busy;         // 0x10

    // SPI Engine Signals
    logic [15:0] tick_cnt;
    logic [3:0]  bit_cnt;
    logic        sck_reg;
    logic [7:0]  shift_reg;    // Active shifter

    // Cross-block communication: Bus -> SPI Engine
    logic        start_transfer;  // Pulse from bus interface

    typedef enum logic { IDLE, TRANSFER } state_e;
    state_e state;

    // Output Assignments
    assign spi_cs_n_o = cs_reg;
    assign spi_sck_o  = sck_reg;
    assign spi_mosi_o = shift_reg[7]; // MSB First

    // ---------------------------------------------------------
    // 2. SPI Engine (Mode 0) - ONLY driver of 'busy'
    // ---------------------------------------------------------
    logic miso_sample;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state    <= IDLE;
            sck_reg  <= 0;
            tick_cnt <= 0;
            bit_cnt  <= 0;
            busy     <= 0;
            rx_data  <= 0;
            shift_reg <= 0;
            miso_sample <= 0;
        end else begin
            case (state)
                IDLE: begin
                    sck_reg  <= 0;
                    tick_cnt <= 0;
                    bit_cnt  <= 0;
                    
                    // Start transfer when bus interface requests it
                    if (start_transfer && !busy) begin
                        busy      <= 1;
                        state     <= TRANSFER;
                        shift_reg <= tx_shift; // Load TX Buffer
                    end
                end

                TRANSFER: begin
                    if (tick_cnt == clk_div) begin
                        tick_cnt <= 0;
                        
                        if (sck_reg == 0) begin
                            // Rising Edge: Sample MISO
                            sck_reg <= 1;
                            miso_sample <= spi_miso_i;
                        end else begin
                            // Falling Edge: Shift Data
                            sck_reg <= 0;
                            
                            if (bit_cnt == 7) begin
                                state   <= IDLE;
                                busy    <= 0;
                                rx_data <= {shift_reg[6:0], miso_sample}; // Capture result
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                                shift_reg <= {shift_reg[6:0], miso_sample}; // Shift Left
                            end
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
            endcase
        end
    end

    // ---------------------------------------------------------
    // 3. Bus Interface
    // ---------------------------------------------------------
    logic read_pending;
    assign req_ready_o = 1'b1;
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            resp_valid_o   <= 0;
            resp_value_o   <= 0;
            
            cs_reg         <= 1;    // Default High
            clk_div        <= 100;  // Default Divider
            tx_shift       <= 0;
            read_pending   <= 0;
            start_transfer <= 0;
        end else begin
            resp_valid_o   <= 0;
            start_transfer <= 0;  // Default: no start pulse

            // // Delayed Response Logic
            // if (read_pending) begin
            //     resp_valid_o <= 1;
            //     read_pending <= 0;
            // end

            if (req_valid_i) begin
                resp_valid_o <= 1;
                if (|req_wstrb_i) begin // WRITE
                    case (req_addr_i[5:0])
                        // TX DATA: Write starts transaction
                        6'h00: begin
                            if (!busy) begin
                                tx_shift       <= req_value_i[7:0];
                                start_transfer <= 1; // Pulse to kick FSM
                            end
                        end
                        // CS CTRL
                        6'h08: cs_reg  <= req_value_i[0];
                        // CLK DIV
                        6'h0C: clk_div <= req_value_i[15:0];
                    endcase
                end else begin // READ
                    read_pending <= 1; // Delay valid by 1 cycle
                    case (req_addr_i[5:0])
                        6'h04: resp_value_o <= {24'b0, rx_data};
                        6'h08: resp_value_o <= {31'b0, cs_reg};
                        6'h0C: resp_value_o <= {16'b0, clk_div};
                        6'h10: resp_value_o <= {31'b0, busy};
                        default: resp_value_o <= 0;
                    endcase
                end
            end
        end
    end

endmodule