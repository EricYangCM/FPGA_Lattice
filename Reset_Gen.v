module ResetGen(
    input wire clk_In,
    output reg rst_n_1_out
);

reg IS_RST_1 = 0;
reg [3:0] RST_1_CNT = 0;  
reg [3:0] RESET_RECOVER_CNT = 0;  // 리셋 복귀를 위한 카운터

always @(posedge clk_In) begin
    if (!IS_RST_1) begin
        if (RST_1_CNT < 10) begin
            RST_1_CNT <= RST_1_CNT + 1;
        end
        else begin
            IS_RST_1 <= 1;
        end
    end
end

always @(posedge clk_In) begin
    if (!IS_RST_1) begin
        rst_n_1_out <= 1;  // 초기 리셋 활성화
        RESET_RECOVER_CNT <= 0; // 리셋 해제 타이머 초기화
    end
    else if (RESET_RECOVER_CNT < 15) begin
        rst_n_1_out <= 0;  // 리셋 해제
        RESET_RECOVER_CNT <= RESET_RECOVER_CNT + 1;
    end
    else begin
        rst_n_1_out <= 1;  // 일정 시간이 지나면 다시 1로 복귀
    end
end

endmodule
