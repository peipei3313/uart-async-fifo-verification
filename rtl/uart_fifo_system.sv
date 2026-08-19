module uart_fifo_system #(
    parameter int RX_CLOCK_FREQ   = 50_000_000,
    parameter int TX_CLOCK_FREQ   = 50_000_000,
    parameter int BAUD_RATE       = 115_200,
    parameter int FIFO_ADDR_WIDTH = 4,

    // FIFO深度16時：
    // almost-full threshold = 16 - 4 = 12
    parameter int FIFO_ALMOST_FULL_THRESHOLD =
        (1 << FIFO_ADDR_WIDTH) - 4,

    // FIFO剩下2筆以下時提出almost-empty警告
    parameter int FIFO_ALMOST_EMPTY_THRESHOLD = 2
)(
    input logic rx_clk,
    input logic tx_clk,
    input logic rst_n,

    // 允許或暫停TX從FIFO取資料
    input logic tx_enable,

    input  logic rx_serial,
    output logic tx_serial,

    output logic fifo_full,
    output logic fifo_empty,

    // Threshold狀態
    output logic fifo_almost_full,
    output logic fifo_almost_empty,

    // 通知上游是否可以繼續傳送
    output logic rx_ready,

    output logic overflow_error,
    output logic framing_error
);

    // UART RX signals
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_busy;

    // FIFO signals
    logic       fifo_wr_en;
    logic [7:0] fifo_wr_data;
    logic       fifo_rd_en;
    logic [7:0] fifo_rd_data;

    // UART TX signals
    logic [7:0] tx_data;
    logic       tx_start;
    logic       tx_busy;
    logic       tx_done;

    typedef enum logic [1:0] {
        TX_IDLE,
        FIFO_READ,
        TX_LAUNCH,
        TX_WAIT
    } tx_state_t;

    tx_state_t tx_state;

    // UART Receiver
    uart_rx #(
        .CLOCK_FREQ (RX_CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE)
    ) uart_rx_inst (
        .clk           (rx_clk),
        .rst_n         (rst_n),
        .rx_serial     (rx_serial),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .rx_busy       (rx_busy),
        .framing_error (framing_error)
    );

    // RX收到一個byte後嘗試寫入FIFO
    assign fifo_wr_en   = rx_valid;
    assign fifo_wr_data = rx_data;

    // 上游流量控制訊號
    //
    // Reset期間：rx_ready = 0
    // FIFO未達門檻：rx_ready = 1
    // FIFO達到almost-full：rx_ready = 0
    assign rx_ready =
        rst_n && !fifo_almost_full;

    // Asynchronous FIFO
    async_fifo #(
        .DATA_WIDTH             (8),
        .ADDR_WIDTH             (FIFO_ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD  (
            FIFO_ALMOST_FULL_THRESHOLD
        ),
        .ALMOST_EMPTY_THRESHOLD (
            FIFO_ALMOST_EMPTY_THRESHOLD
        )
    ) fifo_inst (
        .wr_clk       (rx_clk),
        .wr_rst_n     (rst_n),
        .wr_en        (fifo_wr_en),
        .wr_data      (fifo_wr_data),
        .full         (fifo_full),
        .almost_full  (fifo_almost_full),

        .rd_clk       (tx_clk),
        .rd_rst_n     (rst_n),
        .rd_en        (fifo_rd_en),
        .rd_data      (fifo_rd_data),
        .empty        (fifo_empty),
        .almost_empty (fifo_almost_empty)
    );

    // FIFO滿時若RX仍收到資料，記錄overflow
    // overflow_error為sticky flag，Reset才會清除
    always_ff @(posedge rx_clk or negedge rst_n) begin
        if (!rst_n)
            overflow_error <= 1'b0;
        else if (rx_valid && fifo_full)
            overflow_error <= 1'b1;
    end

    // TX clock domain controller
    always_ff @(posedge tx_clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            fifo_rd_en <= 1'b0;
            tx_start   <= 1'b0;
            tx_data    <= 8'h00;
        end
        else begin
            // 預設只產生一個clock寬度的控制pulse
            fifo_rd_en <= 1'b0;
            tx_start   <= 1'b0;

            case (tx_state)
                TX_IDLE: begin
                    // tx_enable=0時，暫停從FIFO讀取
                    if (tx_enable &&
                        !fifo_empty &&
                        !tx_busy) begin

                        fifo_rd_en <= 1'b1;
                        tx_state   <= FIFO_READ;
                    end
                end

                FIFO_READ: begin
                    // 等待FIFO同步讀出資料
                    tx_state <= TX_LAUNCH;
                end

                TX_LAUNCH: begin
                    tx_data  <= fifo_rd_data;
                    tx_start <= 1'b1;
                    tx_state <= TX_WAIT;
                end

                TX_WAIT: begin
                    if (tx_done)
                        tx_state <= TX_IDLE;
                end

                default: begin
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end

    // UART Transmitter
    uart_tx #(
        .CLOCK_FREQ (TX_CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE)
    ) uart_tx_inst (
        .clk       (tx_clk),
        .rst_n     (rst_n),
        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .tx_serial (tx_serial),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done)
    );

endmodule