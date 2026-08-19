`timescale 1ns/1ps

module uart_tx_tb;

    localparam int CLOCK_FREQ   = 50_000_000;
    localparam int BAUD_RATE    = 115_200;
    localparam int CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;

    logic       clk;
    logic       rst_n;
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_serial;
    logic       tx_busy;
    logic       tx_done;

    logic [7:0] received_data;
    integer error_count;

    uart_tx dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .tx_serial (tx_serial),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done)
    );

    // 50 MHz clock：週期為 20 ns
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // 產生波形檔
    initial begin
        $dumpfile("build/uart_tx.vcd");
        $dumpvars(0, uart_tx_tb);
    end

    // 自動接收並檢查 UART 資料
    task automatic check_uart_byte(input logic [7:0] expected_data);
        integer i;
        begin
            received_data = 8'h00;

            // 等待 start bit：tx_serial 由 1 變成 0
            @(negedge tx_serial);

            // 移動到 start bit 中央
            repeat (CLKS_PER_BIT / 2) @(posedge clk);

            if (tx_serial !== 1'b0) begin
                $display("[FAIL] Invalid start bit");
                error_count = error_count + 1;
            end

            // 在每個 data bit 中央取樣，UART 為 LSB first
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                received_data[i] = tx_serial;
            end

            // 移動到 stop bit 中央並檢查
            repeat (CLKS_PER_BIT) @(posedge clk);

            if (tx_serial !== 1'b1) begin
                $display("[FAIL] Invalid stop bit");
                error_count = error_count + 1;
            end

            // 比對接收到的資料
            if (received_data !== expected_data) begin
                $display(
                    "[FAIL] Expected 0x%02h, received 0x%02h",
                    expected_data,
                    received_data
                );
                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] Expected 0x%02h, received 0x%02h",
                    expected_data,
                    received_data
                );
            end
        end
    endtask

    // 測試流程
    initial begin
        error_count = 0;
        rst_n        = 1'b0;
        tx_start     = 1'b0;
        tx_data      = 8'h00;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        repeat (2) @(posedge clk);

        fork
            // 傳送 A5
            begin
                @(negedge clk);
                tx_data  = 8'hA5;
                tx_start = 1'b1;

                @(negedge clk);
                tx_start = 1'b0;

                wait (tx_done == 1'b1);
            end

            // 同時監聽並檢查傳送結果
            begin
                check_uart_byte(8'hA5);
            end
        join

        repeat (5) @(posedge clk);

        if (error_count == 0)
            $display("[TEST PASS] UART TX verification completed");
        else
            $display("[TEST FAIL] Total errors: %0d", error_count);

        $finish;
    end

endmodule