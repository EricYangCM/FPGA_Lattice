module DMX_IO #(
    parameter CLK_FREQ = 12000000,  // 시스템 클럭
    parameter BAUD_RATE = 250000    // DMX 통신 속도
)(
    output wire [7:0] LED_TP,	// test LED
	output wire TP,
	
	input wire clk,
    input wire rst_n,
    input wire dmx_IsTxMode,  // Tx Mode 제어
    input wire dmx_in,        // DMX 입력 (Rx)
	
	input wire [9:0] dmx_Tx_num_bytes,	// 보낼 데이터 수
	input wire [1:0] dmx_Tx_Hz,		// Tx 주파수

    output wire dmx_out   	// DMX 출력 (Tx)
);



    // **DMX Tx 인스턴스 (송신 모듈)**
    DMX_Tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dmx_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(dmx_IsTxMode),
        .num_bytes(dmx_Tx_num_bytes),
		.EBR_Addr(EBR_Addr_A),
		.EBR_Data(EBR_Data_A),
        .mode_select(dmx_Tx_Hz),
        .tx(dmx_out),  // Tx 출력 연결
		.TP(TP),
        .busy()
    );

/*

    // **DMX Rx 인스턴스 (수신 모듈)**
    DMX_Rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dmx_rx_inst (
        .LED_TP(LED_TP),		// Test LED
		.TP(TP),
		
		.clk(clk),
        .rst_n(rst_n),
        .enable(!dmx_IsTxMode),
        .dmx_data(rx_data), // RX 데이터 신호 연결
        .dmx_in(dmx_in)  // Rx 입력 연결
    );
	*/
	
	// **DMX Tx Dimming Register Map
	//(* ram_style="block" *) reg [8*513-1:0] Tx_DimmingRegMap;
	
	wire[9:0] EBR_Addr_A;
	wire[7:0] EBR_Data_A;
	
	// **EBR 인스턴스 (DMX TX 데이터 저장)**
    EBR_DMX_Tx_DimmingData tx_dimmingData (
        // A포트는 DMX TX 모듈이 사용
        .ClockA(clk),
        .ClockEnA(1'b1),
        .WrA(!dmx_IsTxMode),  // DMX TX 모듈이 읽기 또는 쓰기
        .AddressA(EBR_Addr_A),
        .QA(EBR_Data_A)
    );
	
	
	
	

endmodule
