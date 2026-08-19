module async_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4,

    // FIFO深度16時：
    // almost_full門檻 = 16 - 4 = 12
    parameter int ALMOST_FULL_THRESHOLD =
        (1 << ADDR_WIDTH) - 4,

    // FIFO剩餘資料小於等於2筆時提出警告
    parameter int ALMOST_EMPTY_THRESHOLD = 2
)(
    // 寫入端
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic                  full,
    output logic                  almost_full,

    // 讀取端
    input  logic                  rd_clk,
    input  logic                  rd_rst_n,
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  empty,
    output logic                  almost_empty
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    // Binary與Gray-code pointers
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

    // 將同步後的Gray pointer轉回Binary
    logic [ADDR_WIDTH:0] rptr_bin_sync_w;
    logic [ADDR_WIDTH:0] wptr_bin_sync_r;

    // 各clock domain觀察到的FIFO使用量
    logic [ADDR_WIDTH:0] wr_used_next;
    logic [ADDR_WIDTH:0] rd_used_next;

    logic full_next;
    logic empty_next;
    logic almost_full_next;
    logic almost_empty_next;

    // Gray code轉Binary
    function automatic logic [ADDR_WIDTH:0] gray_to_bin(
        input logic [ADDR_WIDTH:0] gray
    );
        integer bit_index;
        begin
            gray_to_bin[ADDR_WIDTH] = gray[ADDR_WIDTH];

            for (bit_index = ADDR_WIDTH - 1;
                 bit_index >= 0;
                 bit_index = bit_index - 1) begin

                gray_to_bin[bit_index] =
                    gray_to_bin[bit_index + 1] ^
                    gray[bit_index];
            end
        end
    endfunction

    // 計算下一個write pointer、full與almost_full
    always @(*) begin
        // 只使用同步到write domain的read pointer
        rptr_bin_sync_w =
            gray_to_bin(rptr_gray_sync2);

        wptr_bin_next =
            wptr_bin +
            ((wr_en && !full) ? 1'b1 : 1'b0);

        wptr_gray_next =
            (wptr_bin_next >> 1) ^ wptr_bin_next;

        full_next =
            (wptr_gray_next ==
            {~rptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
              rptr_gray_sync2[ADDR_WIDTH-2:0]});

        // FIFO使用量 = write pointer - synchronized read pointer
        wr_used_next =
            wptr_bin_next - rptr_bin_sync_w;

        almost_full_next =
            (wr_used_next >= ALMOST_FULL_THRESHOLD);
    end

    // 寫入資料
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wptr_bin    <= '0;
            wptr_gray   <= '0;
            full        <= 1'b0;
            almost_full <= 1'b0;
        end
        else begin
            if (wr_en && !full)
                memory[wptr_bin[ADDR_WIDTH-1:0]]
                    <= wr_data;

            wptr_bin    <= wptr_bin_next;
            wptr_gray   <= wptr_gray_next;
            full        <= full_next;
            almost_full <= almost_full_next;
        end
    end

    // 將read pointer同步到write clock domain
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

    // 計算下一個read pointer、empty與almost_empty
    always @(*) begin
        // 只使用同步到read domain的write pointer
        wptr_bin_sync_r =
            gray_to_bin(wptr_gray_sync2);

        rptr_bin_next =
            rptr_bin +
            ((rd_en && !empty) ? 1'b1 : 1'b0);

        rptr_gray_next =
            (rptr_bin_next >> 1) ^ rptr_bin_next;

        empty_next =
            (rptr_gray_next == wptr_gray_sync2);

        // FIFO可讀資料量 =
        // synchronized write pointer - read pointer
        rd_used_next =
            wptr_bin_sync_r - rptr_bin_next;

        almost_empty_next =
            (rd_used_next <= ALMOST_EMPTY_THRESHOLD);
    end

    // 讀取資料
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rptr_bin     <= '0;
            rptr_gray    <= '0;
            rd_data      <= '0;
            empty        <= 1'b1;
            almost_empty <= 1'b1;
        end
        else begin
            if (rd_en && !empty)
                rd_data <=
                    memory[rptr_bin[ADDR_WIDTH-1:0]];

            rptr_bin     <= rptr_bin_next;
            rptr_gray    <= rptr_gray_next;
            empty        <= empty_next;
            almost_empty <= almost_empty_next;
        end
    end

    // 將write pointer同步到read clock domain
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