module uart_tx #(
    parameter int CLOCK_FREQ = 50_000_000,
    parameter int BAUD_RATE  = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_start,
    input  logic [7:0] tx_data,

    output logic       tx_serial,
    output logic       tx_busy,
    output logic       tx_done
);

    localparam int CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;
    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    state_t state;

    logic [$clog2(CLKS_PER_BIT)-1:0] baud_counter;
    logic [2:0] bit_index;
    logic [7:0] data_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            baud_counter <= 0;
            bit_index    <= 0;
            data_reg     <= 0;
            tx_serial    <= 1'b1;
            tx_busy      <= 1'b0;
            tx_done      <= 1'b0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                IDLE: begin
                    tx_serial    <= 1'b1;
                    tx_busy      <= 1'b0;
                    baud_counter <= 0;
                    bit_index    <= 0;

                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy  <= 1'b1;
                        state    <= START;
                    end
                end

                START: begin
                    tx_serial <= 1'b0;

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 0;
                        state        <= DATA;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end

                DATA: begin
                    tx_serial <= data_reg[bit_index];

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 0;

                        if (bit_index == 7) begin
                            bit_index <= 0;
                            state     <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end

                STOP: begin
                    tx_serial <= 1'b1;

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 0;
                        tx_busy      <= 1'b0;
                        tx_done      <= 1'b1;
                        state        <= IDLE;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule