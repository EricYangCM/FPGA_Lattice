** top module 설정법
	-> Project -> Active implementation -> Set Top level Unit


module Top_Module (
	
);

    // ? 내부 오실레이터 (12.09MHz) 생성
    wire clk;
    OSCH #(
        .NOM_FREQ("12.09")  // 사용할 클럭 주파수 (2.08MHz 또는 12.09MHz 선택 가능)
    ) internal_osc (
        .STDBY(1'b0),  // 항상 활성화
        .OSC(clk)      // clk 신호에 연결
    );


	parameter CLK_FREQ = 12090000;  // 기본값 12.09MHz


	// Reset Gen
	wire rst_n;
	ResetGen resetGen_inst(
	.clk_In(clk),
	.rst_n_1_out(rst_n)
	);
	
	

endmodule
