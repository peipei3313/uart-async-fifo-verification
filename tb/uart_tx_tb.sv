`timescale 1ns/1ps

module uart_tx_tb;

    logic       clk;
    logic       rst_n;
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_serial;
    logic       tx_busy;
    logic       tx_done;

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

    // 測試流程
    initial begin
        rst_n    = 1'b0;
        tx_start = 1'b0;
        tx_data  = 8'h00;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        repeat (2) @(posedge clk);

        // 傳送 A5
        @(negedge clk);
        tx_data  = 8'hA5;
        tx_start = 1'b1;

        @(negedge clk);
        tx_start = 1'b0;

        wait (tx_done == 1'b1);

        repeat (5) @(posedge clk);
        $finish;
    end

endmodule