`timescale 1ns/1ps

module async_fifo_tb;

    localparam int DATA_WIDTH = 8;
    localparam int ADDR_WIDTH = 4;
    localparam int DEPTH      = 1 << ADDR_WIDTH;

    localparam int ALMOST_FULL_THRESHOLD  = DEPTH - 4;
    localparam int ALMOST_EMPTY_THRESHOLD = 2;

    logic                  wr_clk;
    logic                  wr_rst_n;
    logic                  wr_en;
    logic [DATA_WIDTH-1:0] wr_data;
    logic                  full;
    logic                  almost_full;

    logic                  rd_clk;
    logic                  rd_rst_n;
    logic                  rd_en;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  empty;
    logic                  almost_empty;

    logic [7:0] read_value;
    logic [7:0] expected_value;

    // 用來確認上游停止寫入時pointer沒有移動
    logic [ADDR_WIDTH:0] saved_wptr;

    integer error_count;
    integer i;

    async_fifo #(
        .DATA_WIDTH             (DATA_WIDTH),
        .ADDR_WIDTH             (ADDR_WIDTH),
        .ALMOST_FULL_THRESHOLD  (ALMOST_FULL_THRESHOLD),
        .ALMOST_EMPTY_THRESHOLD (ALMOST_EMPTY_THRESHOLD)
    ) dut (
        .wr_clk       (wr_clk),
        .wr_rst_n     (wr_rst_n),
        .wr_en        (wr_en),
        .wr_data      (wr_data),
        .full         (full),
        .almost_full  (almost_full),

        .rd_clk       (rd_clk),
        .rd_rst_n     (rd_rst_n),
        .rd_en        (rd_en),
        .rd_data      (rd_data),
        .empty        (empty),
        .almost_empty (almost_empty)
    );

    async_fifo_assertions #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) assertion_monitor (
        .wr_clk    (wr_clk),
        .wr_rst_n  (wr_rst_n),
        .wr_en     (wr_en),
        .full      (full),
        .wptr_bin  (dut.wptr_bin),

        .rd_clk    (rd_clk),
        .rd_rst_n  (rd_rst_n),
        .rd_en     (rd_en),
        .empty     (empty),
        .rptr_bin  (dut.rptr_bin)
    );

    // Write clock：100 MHz，週期10 ns
    initial begin
        wr_clk = 1'b0;
        forever #5 wr_clk = ~wr_clk;
    end

    // Read clock：約71.4 MHz，週期14 ns
    initial begin
        rd_clk = 1'b0;
        forever #7 rd_clk = ~rd_clk;
    end

    // 產生GTKWave波形
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

        repeat (2) @(posedge rd_clk);

        // Reset後FIFO應為空
        if (empty === 1'b1)
            $display("[PASS] FIFO is empty after reset");
        else begin
            $display("[FAIL] FIFO should be empty after reset");
            error_count = error_count + 1;
        end

        // Reset後almost_empty應為1
        if (almost_empty === 1'b1)
            $display(
                "[PASS] almost_empty asserted after reset"
            );
        else begin
            $display(
                "[FAIL] almost_empty should be asserted after reset"
            );
            error_count = error_count + 1;
        end

        // FIFO為空時嘗試讀取，pointer應保持不變
        @(negedge rd_clk);
        rd_en = 1'b1;

        @(negedge rd_clk);
        rd_en = 1'b0;

        repeat (2) @(posedge rd_clk);

        // 先寫入12筆，達到almost_full門檻
        for (i = 0;
             i < ALMOST_FULL_THRESHOLD;
             i = i + 1) begin

            fifo_write(i);
        end

        // 寫入12筆後almost_full應為1
        if (almost_full === 1'b1)
            $display(
                "[PASS] almost_full asserted at occupancy %0d",
                ALMOST_FULL_THRESHOLD
            );
        else begin
            $display(
                "[FAIL] almost_full was not asserted at occupancy %0d",
                ALMOST_FULL_THRESHOLD
            );
            error_count = error_count + 1;
        end

        // Testbench模擬會遵守flow control的上游
        // 上游看到almost_full後停止寫入
        saved_wptr = dut.wptr_bin;

        repeat (3) @(posedge wr_clk);

        if (dut.wptr_bin === saved_wptr)
            $display(
                "[PASS] Upstream stopped when almost_full asserted"
            );
        else begin
            $display(
                "[FAIL] Write pointer changed while upstream was stopped"
            );
            error_count = error_count + 1;
        end

        // 故意忽略almost_full警告，再寫入剩下4筆
        // almost_full是預警，不會直接禁止寫入
        for (i = ALMOST_FULL_THRESHOLD;
             i < DEPTH;
             i = i + 1) begin

            fifo_write(i);
        end

        wait (full === 1'b1);
        $display("[PASS] FIFO full flag asserted");

        // FIFO已滿，嘗試寫入EE，應被阻止
        @(negedge wr_clk);
        wr_data = 8'hEE;
        wr_en   = 1'b1;

        @(negedge wr_clk);
        wr_en = 1'b0;

        $display(
            "[PASS] Extra write attempted while FIFO was full"
        );

        // 等待write pointer同步到read domain
        repeat (3) @(posedge rd_clk);

        // FIFO滿時不應為almost_empty
        if (almost_empty === 1'b0)
            $display(
                "[PASS] almost_empty deasserted while FIFO contains data"
            );
        else begin
            $display(
                "[FAIL] almost_empty incorrectly asserted while FIFO was full"
            );
            error_count = error_count + 1;
        end

        // 依序讀出並檢查16筆資料
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

            // 讀取14筆後，FIFO應剩下2筆
            if (i == (DEPTH -
                      ALMOST_EMPTY_THRESHOLD - 1)) begin

                if (almost_empty === 1'b1)
                    $display(
                        "[PASS] almost_empty asserted with %0d entries remaining",
                        ALMOST_EMPTY_THRESHOLD
                    );
                else begin
                    $display(
                        "[FAIL] almost_empty was not asserted with %0d entries remaining",
                        ALMOST_EMPTY_THRESHOLD
                    );
                    error_count = error_count + 1;
                end
            end
        end

        wait (empty === 1'b1);
        $display("[PASS] FIFO empty flag asserted");

        // Read pointer同步回write domain後，
        // almost_full應該解除
        repeat (3) @(posedge wr_clk);

        if (almost_full === 1'b0)
            $display(
                "[PASS] almost_full deasserted after FIFO was drained"
            );
        else begin
            $display(
                "[FAIL] almost_full remained asserted after FIFO was drained"
            );
            error_count = error_count + 1;
        end

        repeat (5) @(posedge rd_clk);

        if (error_count == 0)
            $display(
                "[TEST PASS] FIFO threshold verification completed"
            );
        else
            $display(
                "[TEST FAIL] Total errors: %0d",
                error_count
            );

        $finish;
    end

endmodule