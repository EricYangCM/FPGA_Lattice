module DMX_Rx #(
    parameter CLK_FREQ = 12090000,  // 시스템 클럭 (12.09MHz)
    parameter BAUD_RATE = 250000    // DMX 속도 (250kbps)
)(
    output reg [7:0] LED_TP,       // Test LED
    output reg TP,                 // Test Pin

    input wire clk,                // 시스템 클럭
    input wire rst_n,              // Active Low 리셋
    input wire enable,             // 수신 활성화 신호
    input wire dmx_in /* synthesis syn_force_pads=1 syn_noprune=1 */, // DMX 입력 강제 삭제 방지
    output reg [8*513-1:0] dmx_data, 			// DMX 데이터 저장 (512채널)
	output reg dmx_data_received_bytes_count,	// 받은 바이트 수
	output reg dmx_data_received,				// DMX 데이터 수신 완료 이벤트 플래그
	input wire dmx_data_received_clear			// DMX 데이터 수신 완료 이벤트 플래그 클리어
);

    // **DMX Timing Parameters**
    localparam BIT_TIME   = CLK_FREQ / BAUD_RATE; // 1비트 클럭 사이클 수 (250kbps 기준 4μs)
    localparam HALF_BIT_TIME  = BIT_TIME / 2;     // 중앙 샘플링용 2μs
    localparam BREAK_TIME = (CLK_FREQ / 1000000) * 88;  // BREAK 최소 88μs
    localparam MAB_TIME   = (CLK_FREQ / 1000000) * 8;   // MAB 최소 8μs
    localparam PACKET_END_TIMEOUT = (CLK_FREQ / 1000000) * 16;  // **패킷 종료 타임아웃 16μs**

    // **비트 타이머 크기 자동 계산 (? BIT_TIMER_WIDTH 선언 추가)**
    localparam integer MAX_TIME_1S = CLK_FREQ; 
    localparam integer BIT_TIMER_WIDTH = $clog2(MAX_TIME_1S); // 최소한의 비트 수 계산


	// **내부에 임시로 rx bytes 저장할 레지스터
	reg [8*513-1:0] dmx_data_received_temp;
	reg dmx_data_received_bytes_count_temp;
	

    // **Registers (? BIT_TIMER_WIDTH 기반 레지스터 선언)**
    reg [BIT_TIMER_WIDTH-1:0] bit_timer;
    reg [BIT_TIMER_WIDTH-1:0] bit_sample_timer;
    reg [BIT_TIMER_WIDTH-1:0] break_width, mab_width;
    reg [BIT_TIMER_WIDTH-1:0] packet_timeout;  // **패킷 종료 타이머**
    reg [7:0] shift_reg;
    reg [8:0] byte_count;
    reg [3:0] bit_count;
	reg [1:0] stop_bit_count;
    reg [3:0] state;
	reg [4:0] byte_receive_state;
    reg dmx_prev;
    reg start_bit_detected;

    // **FSM States**
    localparam IDLE         = 0,
               BREAK        = 1,
               MAB          = 2,
               BYTE_RECEIVE = 3,
               PACKET_ANALYZE = 4;
			   
	// **BYTE RECEIVE FSM States**
    localparam BR_STARTBIT_CHECK = 10,
               BR_HALF_WIDTH_DELAY = 11,
               BR_8BIT_RECEIVE = 12,
               BR_STOPBITS_CHECK = 13,
               BR_NEXTBYTE_CHECK = 14;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
			byte_receive_state <= BR_STARTBIT_CHECK;
            byte_count <= 0;
            bit_timer <= 0;
            packet_timeout <= 0;
            shift_reg <= 11'b0;
            dmx_data_received_temp <= 0;
			dmx_data_received_bytes_count_temp <= 0;
			LED_TP <= 8'hFF;
            TP <= 0;
        end else begin
            dmx_prev <= dmx_in;

            case (state)

                // **IDLE 상태: Break 감지 대기**
                IDLE: begin
                    byte_count <= 0;
                    if (dmx_in == 0 && dmx_prev == 1) begin
                        bit_timer <= 0;
                        state <= BREAK;
						byte_receive_state <= BR_STARTBIT_CHECK;
						
						// 바이트 카운터와 임시 버퍼 초기화
						dmx_data_received_temp <= 0;
						dmx_data_received_bytes_count_temp <= 0;
                    end
                end

                // **BREAK 감지 상태**
                BREAK: begin
                    if (dmx_in == 0) begin
                        bit_timer <= bit_timer + 1;
                        if (bit_timer > (CLK_FREQ * 1)) begin
                            state <= IDLE;
                        end
                    end else if (dmx_in == 1 && dmx_prev == 0) begin
                        break_width <= bit_timer;
                        if (bit_timer >= BREAK_TIME) begin
                            state <= MAB;
                            bit_timer <= 0;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                // **MAB 감지 상태**
                MAB: begin
                    if (dmx_in == 1) begin
                        bit_timer <= bit_timer + 1;
                        if (bit_timer > (CLK_FREQ * 1)) begin
                            state <= IDLE;
                        end
                    end else if (dmx_in == 0 && dmx_prev == 1) begin
                        mab_width <= bit_timer;
                        if (bit_timer >= MAB_TIME) begin
                            state <= BYTE_RECEIVE;
                            bit_timer <= 0;
                            packet_timeout <= 0;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                // **BYTE_RECEIVE: Start Code 및 데이터 수신**
				BYTE_RECEIVE: begin
					case(byte_receive_state)
						
						// Start bit check : waiting for falling edge in 16us
						BR_STARTBIT_CHECK: begin
							// MAB나 Stop bit 후에는 무조건 1이므로, 0되는것만 체크하면 됨.
							if(dmx_in == 0) begin
								byte_receive_state <= BR_HALF_WIDTH_DELAY;	// 다음 단계로
								bit_sample_timer <= HALF_BIT_TIME;			// half cycle timer 세팅
							end
							// **패킷 수신 후 일정 시간 (16μs) 동안 추가 데이터 없으면 증가**
							else if (packet_timeout < PACKET_END_TIMEOUT) begin
								packet_timeout <= packet_timeout + 1;  
							end
							// **16μs 동안 start bit가 안옴. 패킷 수신 종료
							else begin
								// 수신 된 bytes가 있음
								if(dmx_data_received_bytes_count_temp != 0) begin
									dmx_data_received_bytes_count <= dmx_data_received_bytes_count_temp;	// 받은 카운터 수 저장
									dmx_data <= dmx_data_received_temp;										// 받은 바이트 배열 저장
									dmx_data_received <= 1;													// 데이터 수신 완료 플래그 셋
								end
								
								state <= IDLE;
							end
						end
						
						// Half cycle 대기 (중앙에서 샘플링 위해서)
						BR_HALF_WIDTH_DELAY: begin
							if(bit_sample_timer > 0) begin
								bit_sample_timer <= bit_sample_timer - 1;
							end
							else begin
								byte_receive_state <= BR_8BIT_RECEIVE;	// 다음 단계로
								bit_timer <= BIT_TIME;					// bit timer set. 처음 비트는 start bit이므로 무시해도 됨
								bit_count <= 0;
							end
						end
						
						// 8-bit Data Sampling
						BR_8BIT_RECEIVE: begin
							// Read 1 bit
							if(bit_timer == 0 && bit_count < 8) begin
								shift_reg <= {dmx_in, shift_reg[7:1]};  // **LSB 우선으로 첫 번째 데이터 비트 수신**
								bit_count <= bit_count + 1;
								bit_timer <= BIT_TIME;					// 4us reset
							end
							// 8-bit 수신 완료. 다음으로 넘어감
							else if(bit_timer == 0 && bit_count == 8) begin
								byte_receive_state <= BR_STOPBITS_CHECK;			// stop bit 체크로 넘어감
								stop_bit_count <= 0;
							end
							// bit timer counter decreases
							else begin
								bit_timer <= bit_timer - 1;	
							end
						end
						
						// 2 stop bits 확인
						BR_STOPBITS_CHECK: begin
							if(bit_timer == 0 && bit_count < 8) begin
								// 두번째 stop bit
								if(dmx_in == 0 && stop_bit_count == 1) begin
									dmx_data_received_temp[dmx_data_received_bytes_count_temp -:8] <= shift_reg;	// 바이트 저장
									dmx_data_received_bytes_count_temp <= dmx_data_received_bytes_count_temp + 1;	// 카운터 증가
									
									byte_receive_state <= BR_STARTBIT_CHECK;	// 다음 바이트 계속 수신
									
									LED_TP = 8'h01;
								end
								// 첫번재 stop bit
								else if(dmx_in == 0) begin
									stop_bit_count <= stop_bit_count + 1;	// stop bit counter
									
									LED_TP = 8'h02;
								end
								// stop bit error
								else begin
									state <= IDLE;
									LED_TP = 8'h03;
								end
								
								bit_timer <= BIT_TIME;					// 4us reset
								TP <= 1;
								LED_TP = 8'h04;
							end
							else begin
								bit_timer <= bit_timer - 1;	
							end
							
						end
					endcase
				end
				
				
				
            endcase
        end
    end
endmodule



