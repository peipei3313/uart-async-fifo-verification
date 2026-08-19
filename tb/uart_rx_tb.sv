`timescale 1ns/1ps

module uart_rx_tb;

    localparam int CLOCK_FREQ = 50_000_000;
    localparam int BAUD_RATE  = 115_200;
    localparam int BIT_PERIOD = 1_000_000_000 / BAUD_RATE;

    logic       clk;
    logic       rst_n;
    logic       rx_serial;
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_busy;
    logic       framing_error;

    integer error_count;

    uart_rx #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx_serial     (rx_serial),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .rx_busy       (rx_busy),
        .framing_error (framing_error)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // 產生波形
    initial begin
        $dumpfile("build/uart_rx.vcd");
        $dumpvars(0, uart_rx_tb);
    end

    // 模擬 UART 傳送一個 byte
    task automatic send_uart_byte(
        input logic [7:0] data,
        input logic       bad_stop_bit
    );
        integer i;
        begin
            // Start bit
            rx_serial = 1'b0;
            #(BIT_PERIOD);

            // 8 data bits，LSB first
            for (i = 0; i < 8; i = i + 1) begin
                rx_serial = data[i];
                #(BIT_PERIOD);
            end

            // Stop bit
            if (bad_stop_bit)
                rx_serial = 1'b0;
            else
                rx_serial = 1'b1;

            #(BIT_PERIOD);

            // 回到 idle
            rx_serial = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    initial begin
        error_count = 0;
        rst_n        = 1'b0;
        rx_serial    = 1'b1;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        repeat (2) @(posedge clk);

        // 測試一：正確接收 A5
        fork
            begin
                send_uart_byte(8'hA5, 1'b0);
            end

            begin
                @(posedge rx_valid);

                if (rx_data === 8'hA5)
                    $display(
                        "[PASS] Expected 0xA5, received 0x%02h",
                        rx_data
                    );
                else begin
                    $display(
                        "[FAIL] Expected 0xA5, received 0x%02h",
                        rx_data
                    );
                    error_count = error_count + 1;
                end
            end
        join

        repeat (5) @(posedge clk);

        // 測試二：錯誤的 stop bit
        fork
            begin
                send_uart_byte(8'h3C, 1'b1);
            end

            begin
                @(posedge framing_error);
                $display("[PASS] Framing error detected");
            end
        join

        repeat (5) @(posedge clk);

        if (error_count == 0)
            $display("[TEST PASS] UART RX verification completed");
        else
            $display("[TEST FAIL] Total errors: %0d", error_count);

        $finish;
    end

endmodule