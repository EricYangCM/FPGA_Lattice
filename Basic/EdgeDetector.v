module EdgeDetector (
    input  wire clk,
    input  wire rst_n,

    input  wire signal_in,        // 비동기 입력 신호
    input  wire edge_type,        // 1: Rising edge, 0: Falling edge

    output reg edge_pulse         // 엣지 발생 시 1클럭 동안 1
);

    // 3단 동기화 레지스터
    reg sync_0, sync_1, sync_2;

    // 이전 상태 저장
    reg signal_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0       <= 1'b0;
            sync_1       <= 1'b0;
            sync_2       <= 1'b0;
            signal_prev  <= 1'b0;
            edge_pulse   <= 1'b0;
        end else begin
            // 3단 동기화
            sync_0 <= signal_in;
            sync_1 <= sync_0;
            sync_2 <= sync_1;

            // edge 검출
            signal_prev <= sync_2;
            if (edge_type) begin
                edge_pulse <= (sync_2 == 1'b1 && signal_prev == 1'b0); // rising
            end else begin
                edge_pulse <= (sync_2 == 1'b0 && signal_prev == 1'b1); // falling
            end
        end
    end

endmodule
