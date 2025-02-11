module DMX_Tx #(
    parameter CLK_FREQ = 12090000,  // 시스템 클럭 Hz (기본값)
    parameter BAUD_RATE = 250000     // DMX 송신 속도 (250kbps)
)(
    input wire clk,               // 시스템 클럭 입력
    input wire rst_n,             // Active-Low 리셋
    input wire enable,            // 송출 활성화 신호 (HIGH: 계속 송출, LOW: 현재 송출 종료 후 멈춤)
    input wire [9:0] num_bytes,   // 송출할 데이터 개수 (1~512)
    input wire [8*512-1:0] dmx_data,  // 전송할 DMX 데이터 (SC + 최대 512채널 데이터)
    input wire [1:0] mode_select, // DMX 모드 선택 (00: 10Hz, 01: 20Hz, 10: 30Hz, 11: 40Hz)
    output reg tx,                // RS-485 송신 신호 (DMX 데이터 송출)
    output reg busy               // 송신 중 여부 (HIGH: 송출 중, LOW: 대기)
);

    // **Baud Rate Generator (250kbps = 4μs per bit)**
    localparam integer BIT_TIME = CLK_FREQ / BAUD_RATE;  // 48 (for 12.09MHz clock)

    // **DMX Timing Constants**
    localparam integer BREAK_TIME = (CLK_FREQ / 1000000) * 180;  // BREAK 기간 (180μs)
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
			if (busy) begin  
				// 현재 전송 중이면 패킷 타이머를 멈추고 기다림
				packet_counter <= 0;  
				start_tx <= 0;
			end else if (packet_counter >= packet_timer) begin
				// ?? busy가 끝났다면 바로 다음 패킷 전송 시작
				start_tx <= 1;  
				packet_counter <= 0;
			end else begin
				start_tx <= 0;
				packet_counter <= packet_counter + 1;
			end
		end else begin
			start_tx <= 0;
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
                        shift_reg <= dmx_data[byte_index*8+:8];  // **첫 바이트 로드**
						tx <= 0;		// Start Code Set
                        state <= 3;
                    end
                end
				
				3: begin // **Start Code (0x00) 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
						bit_index <= bit_index + 1;
						
                        if(bit_index == 8) begin
							tx <= 1;				// set to high for 2 stop bits
							end
						else if(bit_index == 10) begin
							bit_index <= 0;
							state <= 4;		// next
							end
                    end
                end
				
				

                4: begin // **Start Bit 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        tx <= 0;  // **Start Bit 추가**
                        state <= 5;
                    end
                end

                5: begin // **8-bit 데이터 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        tx <= shift_reg[0];
                        shift_reg <= shift_reg >> 1;
                        bit_index <= bit_index + 1;

                        if (bit_index == 8) begin
                            bit_index <= 0;
                            byte_index <= byte_index + 1;
                            state <= 6;
                        end
                    end
                end

                6: begin // **Stop Bit (2-bit HIGH) 전송**
                    if (counter < 2 * BIT_TIME) begin
                        tx <= 1;
                        counter <= counter + 1;
                    end else begin
                        counter <= 0;
                        if (byte_index < num_bytes) begin
                            shift_reg <= dmx_data[byte_index*8+:8];
                            state <= 4;  // **Start Bit부터 다시 전송**
                        end else begin
                            busy <= 0;
                            state <= enable ? 0 : 7;
                        end
                    end
                end
				
                7: begin // **Idle 상태 (Enable OFF)**
                    tx <= 1;
                    state <= 0;
                end

                default: state <= 0;
            endcase
        end
    end
endmodule
