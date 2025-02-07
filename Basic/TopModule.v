module Top_Module (
    output wire TX,          // DMX 송신 핀
    output wire [7:0] LED,    // 8개 LED 출력
	
	output wire clk_1Hz,
	output wire clk_250kHz,
	output wire clk_30Hz,
	output wire clk_40Hz
);

    // ? 내부 오실레이터 (12.09MHz) 생성
    wire clk;
    OSCH #(
        .NOM_FREQ("12.09")  // 사용할 클럭 주파수 (2.08MHz 또는 12.09MHz 선택 가능)
    ) internal_osc (
        .STDBY(1'b0),  // 항상 활성화
        .OSC(clk)      // clk 신호에 연결
    );

	// Reset Gen
	wire rst_n;
	ResetGen resetGen_inst(
	.clk_In(clk),
	.rst_n_1_out(rst_n)
	);
	
	
	// Clock Gen
	ClockGen clock_inst(
	.clk_In(clk),
	.rst_n(rst_n),
	.clk_1Hz(clk_1Hz),
	.clk_250kHz(clk_250kHz),
	.clk_30Hz(clk_30Hz),
	.clk_40Hz(clk_40Hz)
	);
	
 	parameter CLK_FREQ = 12090000;  // 기본값 12.09MHz

	
endmodule
