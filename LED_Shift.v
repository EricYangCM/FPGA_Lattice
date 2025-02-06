module LED_Shift (
    input wire clk,       // 12.09MHz 내부 클럭
    output reg [7:0] LED // 8개 LED 출력 (Active Low)
);

    reg initialized = 0;  // 초기화 여부 확인용 변수
	reg initialized_LED = 0;  // 초기화 여부 확인용 변수
    reg clk_1Hz;
    reg [24:0] clk_1Hz_Counter;

    always @(posedge clk) begin
        if (!initialized) begin
            // ✅ 초기화 수행
            clk_1Hz <= 0; // 1Hz 클럭 초기화
            initialized <= 1; // 초기화 완료 표시
        end else begin
            // ✅ 1Hz 클럭 생성
            clk_1Hz_Counter <= clk_1Hz_Counter + 1;
            if (clk_1Hz_Counter >= 6045000) begin
                clk_1Hz_Counter <= 0;
                clk_1Hz <= ~clk_1Hz; // 1Hz 신호 생성
            end
        end
    end


    always @(posedge clk_1Hz) begin
        if (!initialized_LED) begin
            LED <= 8'b11111110; // ✅ 처음에는 LED를 초기화
			initialized_LED <= 1;
        end else begin
            LED <= {LED[6:0], LED[7]}; // ✅ 왼쪽으로 Shift
        end
    end

endmodule
