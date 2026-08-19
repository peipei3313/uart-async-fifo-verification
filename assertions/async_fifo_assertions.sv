module async_fifo_assertions #(
    parameter int ADDR_WIDTH = 4
)(
    input logic                  wr_clk,
    input logic                  wr_rst_n,
    input logic                  wr_en,
    input logic                  full,
    input logic [ADDR_WIDTH:0]   wptr_bin,

    input logic                  rd_clk,
    input logic                  rd_rst_n,
    input logic                  rd_en,
    input logic                  empty,
    input logic [ADDR_WIDTH:0]   rptr_bin
);

    logic                previous_full;
    logic                previous_wr_en;
    logic [ADDR_WIDTH:0] previous_wptr;
    logic                wr_previous_valid;

    logic                previous_empty;
    logic                previous_rd_en;
    logic [ADDR_WIDTH:0] previous_rptr;
    logic                rd_previous_valid;

    integer write_count;
    integer read_count;
    integer full_count;
    integer empty_count;
    integer blocked_write_count;
    integer blocked_read_count;
    integer write_assertion_errors;
    integer read_assertion_errors;

    initial begin
        write_count            = 0;
        read_count             = 0;
        full_count             = 0;
        empty_count            = 0;
        blocked_write_count    = 0;
        blocked_read_count     = 0;
        write_assertion_errors = 0;
        read_assertion_errors  = 0;
        wr_previous_valid      = 1'b0;
        rd_previous_valid      = 1'b0;
    end

    // Write clock domain assertions
    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin
            wr_previous_valid <= 1'b0;

            assert (full === 1'b0)
            else begin
                $display("[ASSERTION FAIL] full must be 0 during reset");
                write_assertion_errors = write_assertion_errors + 1;
            end
        end
        else begin
            // 上一週期 FIFO 已滿且仍要求寫入，pointer 不可移動
            if (wr_previous_valid &&
                previous_full &&
                previous_wr_en) begin

                assert (wptr_bin == previous_wptr)
                else begin
                    $display(
                        "[ASSERTION FAIL] Write pointer changed while full"
                    );
                    write_assertion_errors =
                        write_assertion_errors + 1;
                end
            end

            // Functional coverage counters
            if (wr_en && !full)
                write_count = write_count + 1;

            if (full)
                full_count = full_count + 1;

            if (wr_en && full)
                blocked_write_count = blocked_write_count + 1;

            previous_full      <= full;
            previous_wr_en     <= wr_en;
            previous_wptr      <= wptr_bin;
            wr_previous_valid  <= 1'b1;
        end
    end

    // Read clock domain assertions
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rd_previous_valid <= 1'b0;

            assert (empty === 1'b1)
            else begin
                $display("[ASSERTION FAIL] empty must be 1 during reset");
                read_assertion_errors = read_assertion_errors + 1;
            end
        end
        else begin
            // 上一週期 FIFO 為空且仍要求讀取，pointer 不可移動
            if (rd_previous_valid &&
                previous_empty &&
                previous_rd_en) begin

                assert (rptr_bin == previous_rptr)
                else begin
                    $display(
                        "[ASSERTION FAIL] Read pointer changed while empty"
                    );
                    read_assertion_errors =
                        read_assertion_errors + 1;
                end
            end

            // Functional coverage counters
            if (rd_en && !empty)
                read_count = read_count + 1;

            if (empty)
                empty_count = empty_count + 1;

            if (rd_en && empty)
                blocked_read_count = blocked_read_count + 1;

            previous_empty     <= empty;
            previous_rd_en     <= rd_en;
            previous_rptr      <= rptr_bin;
            rd_previous_valid  <= 1'b1;
        end
    end

    // 模擬結束時印出 assertion 與 coverage 報告
    final begin
        $display("");
        $display("========== FIFO COVERAGE REPORT ==========");
        $display("Successful writes : %0d", write_count);
        $display("Successful reads  : %0d", read_count);
        $display("Full cycles       : %0d", full_count);
        $display("Empty cycles      : %0d", empty_count);
        $display("Blocked writes    : %0d", blocked_write_count);
        $display("Blocked reads     : %0d", blocked_read_count);
        $display("==========================================");

        if ((write_assertion_errors + read_assertion_errors) == 0)
            $display("[ASSERTION PASS] All FIFO assertions passed");
        else
            $display(
                "[ASSERTION FAIL] Total errors: %0d",
                write_assertion_errors + read_assertion_errors
            );

        if (write_count > 0 &&
            read_count > 0 &&
            full_count > 0 &&
            empty_count > 0 &&
            blocked_write_count > 0 &&
            blocked_read_count > 0)
            $display("[COVERAGE PASS] All planned events were observed");
        else
            $display("[COVERAGE FAIL] Some planned events were not observed");
    end

endmodule