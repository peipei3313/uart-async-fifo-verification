`timescale 1ns/1ps

module uart_fifo_system_tb;

    //localparam int RX_CLOCK_FREQ = 50_000_000;
    //localparam int TX_CLOCK_FREQ = 40_000_000;

    localparam int RX_CLOCK_FREQ = 50_000_000;
    localparam int TX_CLOCK_FREQ = 150_000_000;
    localparam int BAUD_RATE     = 115_200;
    localparam int NUM_BYTES     = 20;



    // 使用RTL實際採用的整數除法計算bit時間
    localparam int RX_CLKS_PER_BIT =
        RX_CLOCK_FREQ / BAUD_RATE;

    localparam int TX_CLKS_PER_BIT =
        TX_CLOCK_FREQ / BAUD_RATE;

    // 使用real避免150 MHz的6.667 ns被整數截成6 ns
    localparam real RX_CLOCK_PERIOD =
        1_000_000_000.0 / RX_CLOCK_FREQ;

    localparam real TX_CLOCK_PERIOD =
        1_000_000_000.0 / TX_CLOCK_FREQ;

    localparam real RX_CLOCK_HALF_PERIOD =
        RX_CLOCK_PERIOD / 2.0;

    localparam real TX_CLOCK_HALF_PERIOD =
        TX_CLOCK_PERIOD / 2.0;

    localparam real RX_BIT_PERIOD =
        RX_CLKS_PER_BIT * RX_CLOCK_PERIOD;

    localparam real TX_BIT_PERIOD =
        TX_CLKS_PER_BIT * TX_CLOCK_PERIOD;

    logic rx_clk;
    logic tx_clk;
    logic rst_n;

    logic rx_serial;
    logic tx_serial;

    logic fifo_full;
    logic fifo_empty;
    logic fifo_almost_full;
    logic fifo_almost_empty;
    logic rx_ready;
    logic overflow_error;
    logic framing_error;

    logic [7:0] expected_data [0:NUM_BYTES-1];
    logic [7:0] received_data;

    integer error_count;
    integer i;

    uart_fifo_system #(
        .RX_CLOCK_FREQ   (RX_CLOCK_FREQ),
        .TX_CLOCK_FREQ   (TX_CLOCK_FREQ),
        .BAUD_RATE       (BAUD_RATE),
        .FIFO_ADDR_WIDTH (4)
    ) dut (
        .rx_clk          (rx_clk),
        .tx_clk          (tx_clk),
        .rst_n           (rst_n),
        .rx_serial       (rx_serial),
        .tx_serial       (tx_serial),
        .fifo_full         (fifo_full),
        .fifo_empty        (fifo_empty),
        .fifo_almost_full  (fifo_almost_full),
        .fifo_almost_empty (fifo_almost_empty),
        .rx_ready          (rx_ready),
        .overflow_error    (overflow_error),
        .framing_error     (framing_error)
    );

    // RX clock：50 MHz，週期20 ns
    initial begin
        rx_clk = 1'b0;

        forever #(RX_CLOCK_HALF_PERIOD)
            rx_clk = ~rx_clk;
    end

    // TX clock：150 MHz，週期約6.667 ns
    initial begin
        tx_clk = 1'b0;

        forever #(TX_CLOCK_HALF_PERIOD)
            tx_clk = ~tx_clk;
    end

    // 產生GTKWave波形
    initial begin
        $dumpfile("build/uart_fifo_system.vcd");
        $dumpvars(0, uart_fifo_system_tb);
    end

    // 從外部送一個UART byte到系統RX
    task automatic send_rx_byte(input logic [7:0] data);
        integer bit_index;
        begin
            // Start bit
            rx_serial = 1'b0;
            #(RX_BIT_PERIOD);

            // 8 data bits，LSB first
            for (bit_index = 0;
                 bit_index < 8;
                 bit_index = bit_index + 1) begin

                rx_serial = data[bit_index];
                #(RX_BIT_PERIOD);
            end

            // Stop bit
            rx_serial = 1'b1;
            #(RX_BIT_PERIOD);
        end
    endtask

    // 解碼系統TX輸出的一個UART byte
    task automatic receive_tx_byte(output logic [7:0] data);
        integer bit_index;
        begin
            data = 8'h00;

            // 等待TX的start bit
            @(negedge tx_serial);

            // 移動到start bit中央
            #(TX_BIT_PERIOD / 2);

            if (tx_serial !== 1'b0) begin
                $display("[FAIL] Invalid TX start bit");
                error_count = error_count + 1;
            end

            // 在每個data bit中央取樣
            for (bit_index = 0;
                 bit_index < 8;
                 bit_index = bit_index + 1) begin

                #(TX_BIT_PERIOD);
                data[bit_index] = tx_serial;
            end

            // 移動到stop bit中央
            #(TX_BIT_PERIOD);

            if (tx_serial !== 1'b1) begin
                $display("[FAIL] Invalid TX stop bit");
                error_count = error_count + 1;
            end
        end
    endtask

    // 防止錯誤造成模擬無限等待
    initial begin
        #50_000_000;
        $display("[TEST FAIL] Simulation timeout");
        $finish;
    end

    initial begin
        error_count = 0;
        rst_n        = 1'b0;
        rx_serial    = 1'b1;

        // 固定邊界值：保證重要資料型態一定被測到
        expected_data[0] = 8'h00;  // 全部為0
        expected_data[1] = 8'hFF;  // 全部為1
        expected_data[2] = 8'hAA;  // 10101010
        expected_data[3] = 8'h55;  // 01010101
        expected_data[4] = 8'hA5;  // 混合資料
        expected_data[5] = 8'h3C;  // 混合資料

        // 其餘14筆隨機產生
        for (i = 6; i < NUM_BYTES; i = i + 1) begin
            expected_data[i] =
                $urandom_range(8'hFF, 8'h00);

            $display(
                "[INFO] Random byte %0d = 0x%02h",
                i,
                expected_data[i]
            );
        end

        repeat (5) @(posedge rx_clk);
        repeat (5) @(posedge tx_clk);
        rst_n = 1'b1;

        repeat (5) @(posedge rx_clk);
        if (rx_ready === 1'b1)
            $display(
                "[PASS] RX upstream interface is ready"
            );
        else begin
            $display(
                "[FAIL] rx_ready should be asserted after reset"
            );
            error_count = error_count + 1;
        end

                fork
            // 將5筆資料送進UART RX
            begin : sender_process
                integer send_index;

                for (send_index = 0;
                     send_index < NUM_BYTES;
                     send_index = send_index + 1) begin

                    // 模擬會遵守Flow Control的上游設備
                    wait (rx_ready === 1'b1);

                    send_rx_byte(expected_data[send_index]);
                end
            end

            // 從UART TX接收並自動比對
            begin : receiver_process
                integer receive_index;

                for (receive_index = 0;
                     receive_index < NUM_BYTES;
                     receive_index = receive_index + 1) begin

                    receive_tx_byte(received_data);

                    if (received_data ===
                        expected_data[receive_index]) begin

                        $display(   
                            "[PASS] Byte %0d: expected 0x%02h, received 0x%02h",
                            receive_index,
                            expected_data[receive_index],
                            received_data
                        );
                    end
                    else begin
                        $display(
                            "[FAIL] Byte %0d: expected 0x%02h, received 0x%02h",
                            receive_index,
                            expected_data[receive_index],
                            received_data
                        );

                        error_count = error_count + 1;
                    end
                end
            end
        join
        repeat (10) @(posedge tx_clk);

        if (overflow_error) begin
            $display("[FAIL] Unexpected FIFO overflow");
            error_count = error_count + 1;
        end

        if (framing_error) begin
            $display("[FAIL] Unexpected UART framing error");
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display(
                "[TEST PASS] UART FIFO end-to-end verification completed"
            );
        else
            $display(
                "[TEST FAIL] Total errors: %0d",
                error_count
            );

        $finish;
    end

endmodule