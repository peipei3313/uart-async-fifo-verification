module uart_rx #(
    parameter int CLOCK_FREQ = 50_000_000,
    parameter int BAUD_RATE  = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx_serial,

    output logic [7:0] rx_data,
    output logic       rx_valid,
    output logic       rx_busy,
    output logic       framing_error
);

    localparam int CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;

    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    } state_t;

    state_t state;

    integer     clk_count;
    logic [2:0] bit_index;
    logic [7:0] received_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            clk_count     <= 0;
            bit_index     <= 3'd0;
            received_data <= 8'h00;
            rx_data       <= 8'h00;
            rx_valid      <= 1'b0;
            rx_busy       <= 1'b0;
            framing_error <= 1'b0;
        end
        else begin
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    rx_busy       <= 1'b0;
                    framing_error <= 1'b0;
                    clk_count     <= 0;
                    bit_index     <= 3'd0;

                    if (rx_serial == 1'b0) begin
                        rx_busy <= 1'b1;
                        state   <= START_BIT;
                    end
                end

                START_BIT: begin
                    if (clk_count == (CLKS_PER_BIT / 2) - 1) begin
                        clk_count <= 0;

                        if (rx_serial == 1'b0)
                            state <= DATA_BITS;
                        else begin
                            rx_busy <= 1'b0;
                            state   <= IDLE;
                        end
                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end
                end

                DATA_BITS: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count                <= 0;
                        received_data[bit_index] <= rx_serial;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state     <= STOP_BIT;
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STOP_BIT: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        rx_busy   <= 1'b0;

                        if (rx_serial == 1'b1) begin
                            rx_data  <= received_data;
                            rx_valid <= 1'b1;
                        end
                        else begin
                            framing_error <= 1'b1;
                        end

                        state <= IDLE;
                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule