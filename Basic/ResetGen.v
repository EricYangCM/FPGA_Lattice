module ClockGen #(
    parameter CLK_FREQ = 12090000  // 기본 메인 클럭: 12.09MHz (Hz 단위)
)(
    input wire clk_In,      // 메인 클럭 입력
    input wire rst_n,       // Active-Low 리셋
    output reg clk_1Hz,     // 1Hz 출력 클럭
    output reg clk_250kHz,  // 250kHz 출력 클럭
    output reg clk_30Hz,    // 30Hz 출력 클럭
    output reg clk_40Hz     // 40Hz 출력 클럭
);

    // 원하는 주파수로 나누는 카운트 계산
    localparam COUNT_1Hz      = CLK_FREQ / 2;       // 1Hz
    localparam COUNT_250kHz   = CLK_FREQ / 250000 / 2;  // 250kHz
    localparam COUNT_30Hz     = CLK_FREQ / 30 / 2;  // 30Hz
    localparam COUNT_40Hz     = CLK_FREQ / 40 / 2;  // 40Hz

    // 필요한 만큼의 비트 크기 자동 계산 (최적화)
    localparam WIDTH_1Hz      = $clog2(COUNT_1Hz);
    localparam WIDTH_250kHz   = $clog2(COUNT_250kHz);
    localparam WIDTH_30Hz     = $clog2(COUNT_30Hz);
    localparam WIDTH_40Hz     = $clog2(COUNT_40Hz);

    // 카운터 정의
    reg [WIDTH_1Hz-1:0] counter_1Hz;
    reg [WIDTH_250kHz-1:0] counter_250kHz;
    reg [WIDTH_30Hz-1:0] counter_30Hz;
    reg [WIDTH_40Hz-1:0] counter_40Hz;

    always @(posedge clk_In or negedge rst_n) begin
        if (!rst_n) begin
            counter_1Hz <= 0;
            counter_250kHz <= 0;
            counter_30Hz <= 0;
            counter_40Hz <= 0;
            clk_1Hz <= 0;
            clk_250kHz <= 0;
            clk_30Hz <= 0;
            clk_40Hz <= 0;
        end else begin
            // 1Hz 클럭 생성
            if (counter_1Hz < COUNT_1Hz - 1)
                counter_1Hz <= counter_1Hz + 1;
            else begin
                counter_1Hz <= 0;
                clk_1Hz <= ~clk_1Hz;
            end

            // 250kHz 클럭 생성
            if (counter_250kHz < COUNT_250kHz - 1)
                counter_250kHz <= counter_250kHz + 1;
            else begin
                counter_250kHz <= 0;
                clk_250kHz <= ~clk_250kHz;
            end

            // 30Hz 클럭 생성
            if (counter_30Hz < COUNT_30Hz - 1)
                counter_30Hz <= counter_30Hz + 1;
            else begin
                counter_30Hz <= 0;
                clk_30Hz <= ~clk_30Hz;
            end

            // 40Hz 클럭 생성
            if (counter_40Hz < COUNT_40Hz - 1)
                counter_40Hz <= counter_40Hz + 1;
            else begin
                counter_40Hz <= 0;
                clk_40Hz <= ~clk_40Hz;
            end
        end
    end

endmodule
