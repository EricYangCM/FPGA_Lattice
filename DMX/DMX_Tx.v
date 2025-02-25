module DMX_Tx #(
    parameter CLK_FREQ = 12090000,  // 시스템 클럭 Hz (기본값)
    parameter BAUD_RATE = 250000     // DMX 송신 속도 (250kbps)
)(
    input wire clk,               // 시스템 클럭 입력
    input wire rst_n,             // Active-Low 리셋
    input wire enable,            // 송출 활성화 신호 (HIGH: 계속 송출, LOW: 현재 송출 종료 후 멈춤)
    input wire [9:0] num_bytes,   // 송출할 데이터 개수 (1~512)
	input wire [7:0] EBR_Data,			// DMX 데이터의 EBR Data
	
    input wire [1:0] mode_select, // DMX 모드 선택 (00: 10Hz, 01: 20Hz, 10: 30Hz, 11: 40Hz)
    output reg tx,                // RS-485 송신 신호 (DMX 데이터 송출)
    output reg busy,               // 송신 중 여부 (HIGH: 송출 중, LOW: 대기)
	output reg [9:0] EBR_Addr,			// DMX 데이터 EBR의 Address
	output reg TP
);

    // **Baud Rate Generator (250kbps = 4μs per bit)**
    localparam integer BIT_TIME = CLK_FREQ / BAUD_RATE;  // 48 (for 12.09MHz clock)

    // **DMX Timing Constants**
	localparam integer BREAK_TIME = (CLK_FREQ / 1000000) * 100;  // BREAK 기간 (100μs)
    localparam integer MAB_TIME   = (CLK_FREQ / 1000000) * 20;   // MARK After Break (20μs)

    reg [31:0] packet_timer;

    always @(*) begin
        case (mode_select)
            2'b00: packet_timer = CLK_FREQ / 10;   
            2'b01: packet_timer = CLK_FREQ / 20;   
            2'b10: packet_timer = CLK_FREQ / 30;   
            2'b11: packet_timer = CLK_FREQ / 40;   
            default: packet_timer = CLK_FREQ / 40;
        endcase
    end

    // **레지스터 변수 선언**
    reg [15:0] counter;
    reg [31:0] packet_counter;
    reg [5:0] state;
    reg [7:0] shift_reg;
    reg [9:0] byte_index;  // **현재 몇 번째 바이트인지 추적**
    reg [3:0] bit_index;
    reg start_tx;

    // **enable 신호에 따라 자동 송출 제어**
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			packet_counter <= 0;
			start_tx <= 0;
		end else if (enable) begin
			if (packet_counter > packet_timer) begin
					start_tx <= 1;
					packet_counter <= 0;  // 타이머 리셋
			end else begin
				packet_counter <= packet_counter + 1; // 항상 증가
				start_tx <= 0;	// 1 clock 동안만 set
			end
		end
	end


    // **FSM - num_bytes 개수만큼 송신**
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            tx <= 1;
            busy <= 0;
            counter <= 0;
            byte_index <= 0;
            bit_index <= 0;
            shift_reg <= 0;
        end else begin
            case (state)
                0: begin
                    if (start_tx) begin
						state <= 1;
                        busy <= 1;
                        counter <= 0;
                        byte_index <= 0;
						bit_index <= 0;
						EBR_Addr <= 0;  // Data Address 초기화
                    end
                end

                1: begin // **BREAK 전송**
                    tx <= 0;
                    if (counter < BREAK_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        state <= 2;
                    end
                end

                2: begin // **MAB 전송**
                    tx <= 1;
                    if (counter < MAB_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        shift_reg <= EBR_Data;  // **첫 바이트 로드**
						EBR_Addr <= EBR_Addr + 1;	// 바이트 주소 이동
                        state <= 3;
                    end
                end
				

                3: begin // **Start Bit 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        tx <= 0;  // **Start Bit 추가**
                        state <= 4;
                    end
                end

                4: begin // **8-bit 데이터 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        tx <= shift_reg[0];
                        shift_reg <= shift_reg >> 1;
                        bit_index <= bit_index + 1;

                        if (bit_index == 8) begin
                            bit_index <= 0;
							tx <= 1;		// set stop bit
                            byte_index <= byte_index + 1;
                            state <= 5;
                        end
						
						TP <= !TP;
                    end
                end

                5: begin // **Stop Bit (2-bit HIGH) 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        if (byte_index < num_bytes) begin
                            shift_reg <= EBR_Data;  // **첫 바이트 로드**
							EBR_Addr <= EBR_Addr + 1;	// 바이트 주소 이동
                            state <= 3;  // **Start Bit부터 다시 전송**
                        end else begin
                            busy <= 0;
                            state <= enable ? 0 : 6;
                        end
                    end
                end
				
                6: begin // **Idle 상태 (Enable OFF)**
                    tx <= 1;
                    state <= 0;
                end

                default: state <= 0;
            endcase
        end
    end
endmodule
