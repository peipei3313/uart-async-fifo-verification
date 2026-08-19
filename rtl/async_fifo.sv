module async_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
)(
    // 寫入端
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic                  full,

    // 讀取端
    input  logic                  rd_clk,
    input  logic                  rd_rst_n,
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  empty
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    // Binary 與 Gray-code pointers
    logic [ADDR_WIDTH:0] wptr_bin;
    logic [ADDR_WIDTH:0] wptr_bin_next;
    logic [ADDR_WIDTH:0] wptr_gray;
    logic [ADDR_WIDTH:0] wptr_gray_next;

    logic [ADDR_WIDTH:0] rptr_bin;
    logic [ADDR_WIDTH:0] rptr_bin_next;
    logic [ADDR_WIDTH:0] rptr_gray;
    logic [ADDR_WIDTH:0] rptr_gray_next;

    // 跨時脈同步器
    logic [ADDR_WIDTH:0] rptr_gray_sync1;
    logic [ADDR_WIDTH:0] rptr_gray_sync2;
    logic [ADDR_WIDTH:0] wptr_gray_sync1;
    logic [ADDR_WIDTH:0] wptr_gray_sync2;

    logic full_next;
    logic empty_next;

    // 計算下一個 write pointer
    always @(*) begin
        wptr_bin_next =
            wptr_bin + ((wr_en && !full) ? 1'b1 : 1'b0);

        wptr_gray_next =
            (wptr_bin_next >> 1) ^ wptr_bin_next;

        full_next =
            (wptr_gray_next ==
            {~rptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
              rptr_gray_sync2[ADDR_WIDTH-2:0]});
    end

    // 寫入資料
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wptr_bin  <= '0;
            wptr_gray <= '0;
            full      <= 1'b0;
        end
        else begin
            if (wr_en && !full)
                memory[wptr_bin[ADDR_WIDTH-1:0]] <= wr_data;

            wptr_bin  <= wptr_bin_next;
            wptr_gray <= wptr_gray_next;
            full      <= full_next;
        end
    end

    // 將 read pointer 同步到 write clock domain
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rptr_gray_sync1 <= '0;
            rptr_gray_sync2 <= '0;
        end
        else begin
            rptr_gray_sync1 <= rptr_gray;
            rptr_gray_sync2 <= rptr_gray_sync1;
        end
    end

    // 計算下一個 read pointer
    always @(*) begin
        rptr_bin_next =
            rptr_bin + ((rd_en && !empty) ? 1'b1 : 1'b0);

        rptr_gray_next =
            (rptr_bin_next >> 1) ^ rptr_bin_next;

        empty_next = (rptr_gray_next == wptr_gray_sync2);
    end

    // 讀取資料
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rptr_bin  <= '0;
            rptr_gray <= '0;
            rd_data   <= '0;
            empty     <= 1'b1;
        end
        else begin
            if (rd_en && !empty)
                rd_data <= memory[rptr_bin[ADDR_WIDTH-1:0]];

            rptr_bin  <= rptr_bin_next;
            rptr_gray <= rptr_gray_next;
            empty     <= empty_next;
        end
    end

    // 將 write pointer 同步到 read clock domain
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wptr_gray_sync1 <= '0;
            wptr_gray_sync2 <= '0;
        end
        else begin
            wptr_gray_sync1 <= wptr_gray;
            wptr_gray_sync2 <= wptr_gray_sync1;
        end
    end

endmodule