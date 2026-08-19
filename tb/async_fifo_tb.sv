`timescale 1ns/1ps

module async_fifo_tb;

    localparam int DATA_WIDTH = 8;
    localparam int ADDR_WIDTH = 4;
    localparam int DEPTH      = 1 << ADDR_WIDTH;

    logic                  wr_clk;
    logic                  wr_rst_n;
    logic                  wr_en;
    logic [DATA_WIDTH-1:0] wr_data;
    logic                  full;

    logic                  rd_clk;
    logic                  rd_rst_n;
    logic                  rd_en;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  empty;

    logic [7:0] read_value;
    logic [7:0] expected_value;
    integer error_count;
    integer i;

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .full     (full),

        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .empty    (empty)
    );

    // Write clock：100 MHz，週期 10 ns
    initial begin
        wr_clk = 1'b0;
        forever #5 wr_clk = ~wr_clk;
    end

    // Read clock：約 71.4 MHz，週期 14 ns
    initial begin
        rd_clk = 1'b0;
        forever #7 rd_clk = ~rd_clk;
    end

    // 產生 GTKWave 波形
    initial begin
        $dumpfile("build/async_fifo.vcd");
        $dumpvars(0, async_fifo_tb);
    end

    // 寫入一筆資料
    task automatic fifo_write(input logic [7:0] data);
        begin
            @(negedge wr_clk);

            while (full)
                @(negedge wr_clk);

            wr_data = data;
            wr_en   = 1'b1;

            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    // 讀取一筆資料
    task automatic fifo_read(output logic [7:0] data);
        begin
            @(negedge rd_clk);

            while (empty)
                @(negedge rd_clk);

            rd_en = 1'b1;

            @(negedge rd_clk);
            data  = rd_data;
            rd_en = 1'b0;
        end
    endtask

    // 防止模擬因錯誤而永遠等待
    initial begin
        #1_000_000;
        $display("[TEST FAIL] Simulation timeout");
        $finish;
    end

    initial begin
        error_count = 0;

        wr_rst_n = 1'b0;
        rd_rst_n = 1'b0;
        wr_en    = 1'b0;
        rd_en    = 1'b0;
        wr_data  = 8'h00;

        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1'b1;

        repeat (5) @(posedge rd_clk);
        rd_rst_n = 1'b1;

        // Reset 後 FIFO 應該是空的
        repeat (2) @(posedge rd_clk);

        if (empty === 1'b1)
            $display("[PASS] FIFO is empty after reset");
        else begin
            $display("[FAIL] FIFO should be empty after reset");
            error_count = error_count + 1;
        end

        // 寫入 16 筆資料，填滿 FIFO
        for (i = 0; i < DEPTH; i = i + 1)
            fifo_write(i);

        wait (full === 1'b1);
        $display("[PASS] FIFO full flag asserted");

        // FIFO 已滿，嘗試寫入 EE，應該被阻止
        @(negedge wr_clk);
        wr_data = 8'hEE;
        wr_en   = 1'b1;

        @(negedge wr_clk);
        wr_en = 1'b0;

        $display("[PASS] Extra write attempted while FIFO was full");

        // 依序讀出並檢查 16 筆資料
        for (i = 0; i < DEPTH; i = i + 1) begin
            expected_value = i;
            fifo_read(read_value);

            if (read_value !== expected_value) begin
                $display(
                    "[FAIL] Expected 0x%02h, received 0x%02h",
                    expected_value,
                    read_value
                );
                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] Expected 0x%02h, received 0x%02h",
                    expected_value,
                    read_value
                );
            end
        end

        wait (empty === 1'b1);
        $display("[PASS] FIFO empty flag asserted");

        repeat (5) @(posedge rd_clk);

        if (error_count == 0)
            $display("[TEST PASS] Asynchronous FIFO verification completed");
        else
            $display("[TEST FAIL] Total errors: %0d", error_count);

        $finish;
    end

endmodule