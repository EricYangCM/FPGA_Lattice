module ResetGen(
    input wire clk_In,
    input wire clk_lock,             // PLL의 Lock 신호
    output reg rst_n_1_out
);

parameter RESET_HOLD_CYCLES = 100;  // LOCK 후 리셋 해제까지 기다릴 사이클 수

reg [7:0] lock_wait_cnt = 0;
reg lock_synced = 0;                // LOCK이 한 번이라도 올라왔는지 감지
reg [7:0] reset_hold_cnt = 0;
reg rst_release = 0;

always @(posedge clk_In) begin
    // PLL이 LOCK된 후 한번만 latch
    if (clk_lock && !lock_synced) begin
        lock_synced <= 1;
    end
end

always @(posedge clk_In) begin
    if (!lock_synced) begin
        // PLL이 아직 안정되지 않음: 리셋 유지
        rst_n_1_out <= 0;
        reset_hold_cnt <= 0;
    end
    else if (reset_hold_cnt < RESET_HOLD_CYCLES) begin
        // PLL이 LOCK된 후, 몇 클럭 기다리기
        rst_n_1_out <= 0;
        reset_hold_cnt <= reset_hold_cnt + 1;
    end
    else begin
        // 안정화 시간 지난 후 리셋 해제
        rst_n_1_out <= 1;
    end
end

endmodule
