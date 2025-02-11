module DMX_IO #(
    parameter CLK_FREQ = 12000000,  // 시스템 클럭
    parameter BAUD_RATE = 250000    // DMX 통신 속도
)(
    input wire clk,
    input wire rst_n,
	input wire dmx_IsTxMode,	// Tx Mode ?
	
    output wire dmx_out,   	// DMX 출력 (Tx)
    output reg [8*512-1:0] dmx_register_Tx, // 1차원 벡터로 선언 (512바이트 데이터 저장)
	
	output wire dmx_in,   	// DMX 입력 (Rx)
	output reg [8*512-1:0] dmx_register_Rx // 1차원 벡터로 선언 (512바이트 데이터 저장)
);

    // **DMX Tx 모드 및 제어 변수**
    reg [1:0] tempModeSelect = 2'b11;  // 기본 40Hz 설정
    reg [9:0] num_bytes = 512;
    reg tempEN = 1;

    // **DMX Tx 인스턴스 (송신 모듈)**
    DMX_Tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dmx_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(tempEN),
        .num_bytes(num_bytes),
        .dmx_data(dmx_register_Tx), // 1차원 벡터로 전달
        .mode_select(tempModeSelect),
        .tx(dmx_out),  // Tx 출력 연결
        .busy()
    );

    // **초기값 설정 (dmx_register_Tx 초기화)**
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmx_register_Tx <= {512{8'h00}};  // 전체를 0x00으로 초기화
        end
    end

endmodule
