`timescale 1ns/1ps

module uart_fifo_overflow_tb;

    localparam int RX_CLOCK_FREQ = 50_000_000;
    localparam int TX_CLOCK_FREQ = 150_000_000;
    localparam int BAUD_RATE     = 115_200;

    localparam int RX_CLKS_PER_BIT =
        RX_CLOCK_FREQ / BAUD_RATE;

    localparam real RX_CLOCK_PERIOD =
        1_000_000_000.0 / RX_CLOCK_FREQ;

    localparam real TX_CLOCK_PERIOD =
        1_000_000_000.0 / TX_CLOCK_FREQ;

    localparam real RX_BIT_PERIOD =
        RX_CLKS_PER_BIT * RX_CLOCK_PERIOD;

    logic rx_clk;
    logic tx_clk;
    logic rst_n;
    logic tx_enable;

    logic rx_serial;
    logic tx_serial;

    logic fifo_full;
    logic fifo_empty;
    logic fifo_almost_full;
    logic fifo_almost_empty;
    logic rx_ready;
    logic overflow_error;
    logic framing_error;

    logic [4:0] saved_write_pointer;

    integer error_count;
    integer send_index;

    uart_fifo_system #(
        .RX_CLOCK_FREQ   (RX_CLOCK_FREQ),
        .TX_CLOCK_FREQ   (TX_CLOCK_FREQ),
        .BAUD_RATE       (BAUD_RATE),
        .FIFO_ADDR_WIDTH (4)
    ) dut (
        .rx_clk           (rx_clk),
        .tx_clk           (tx_clk),
        .rst_n            (rst_n),
        .tx_enable        (tx_enable),

        .rx_serial        (rx_serial),
        .tx_serial        (tx_serial),

        .fifo_full        (fifo_full),
        .fifo_empty       (fifo_empty),
        .fifo_almost_full (fifo_almost_full),
        .fifo_almost_empty(fifo_almost_empty),
        .rx_ready         (rx_ready),

        .overflow_error   (overflow_error),
        .framing_error    (framing_error)
    );

    // RX clock：50 MHz
    initial begin
        rx_clk = 1'b0;

        forever #(RX_CLOCK_PERIOD / 2.0)
            rx_clk = ~rx_clk;
    end

    // TX clock：150 MHz
    initial begin
        tx_clk = 1'b0;

        forever #(TX_CLOCK_PERIOD / 2.0)
            tx_clk = ~tx_clk;
    end

    // GTKWave
    initial begin
        $dumpfile("build/uart_fifo_overflow.vcd");
        $dumpvars(0, uart_fifo_overflow_tb);
    end

    // 模擬外部UART送入一個Byte
    task automatic send_rx_byte(
        input logic [7:0] data
    );
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

    // 防止錯誤造成永久等待
    initial begin
        #5_000_000;
        $display("[TEST FAIL] Simulation timeout");
        $finish;
    end

    initial begin
        error_count = 0;

        rst_n      = 1'b0;
        tx_enable  = 1'b0;
        rx_serial  = 1'b1;

        repeat (5) @(posedge rx_clk);
        repeat (5) @(posedge tx_clk);

        rst_n = 1'b1;

        repeat (5) @(posedge rx_clk);

        // 第一階段：寫入12筆，達到Threshold
        for (send_index = 0;
             send_index < 12;
             send_index = send_index + 1) begin

            // 故意不檢查rx_ready
            send_rx_byte(send_index);
        end

        wait (fifo_almost_full === 1'b1);

        $display(
            "[PASS] almost_full asserted after 12 bytes"
        );

        if (rx_ready === 1'b0)
            $display(
                "[PASS] rx_ready deasserted at threshold"
            );
        else begin
            $display(
                "[FAIL] rx_ready should be 0 at threshold"
            );
            error_count = error_count + 1;
        end

        // 第二階段：忽略rx_ready，再送4筆直到FIFO滿
        for (send_index = 12;
             send_index < 16;
             send_index = send_index + 1) begin

            send_rx_byte(send_index);
        end

        wait (fifo_full === 1'b1);

        $display(
            "[PASS] FIFO full asserted after 16 bytes"
        );

        saved_write_pointer =
            dut.fifo_inst.wptr_bin;

        // 第17筆：故意在FIFO滿時繼續傳送
        send_rx_byte(8'hDE);

        repeat (5) @(posedge rx_clk);

        // 檢查Overflow error
        if (overflow_error === 1'b1)
            $display(
                "[PASS] Overflow error detected"
            );
        else begin
            $display(
                "[FAIL] Overflow error was not detected"
            );
            error_count = error_count + 1;
        end

        // FIFO滿時，write pointer不能前進
        if (dut.fifo_inst.wptr_bin ===
            saved_write_pointer) begin

            $display(
                "[PASS] Extra byte was blocked while FIFO was full"
            );
        end
        else begin
            $display(
                "[FAIL] Write pointer changed while FIFO was full"
            );
            error_count = error_count + 1;
        end

        if (framing_error === 1'b1) begin
            $display(
                "[FAIL] Unexpected UART framing error"
            );
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display(
                "[TEST PASS] UART FIFO overflow protection completed"
            );
        else
            $display(
                "[TEST FAIL] Total errors: %0d",
                error_count
            );

        $finish;
    end

endmodule