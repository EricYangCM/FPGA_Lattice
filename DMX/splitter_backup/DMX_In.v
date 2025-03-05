module DMX_Input_Module #(
	parameter CLK_FREQ = 12000000,  // 시스템 클럭
	parameter BAUD_RATE = 250000    // DMX 통신 속도
)(
	input wire clk,
    input wire rst_n,
	input wire DMX_Input_Signal,	// DMX 입력 신호 핀
	
	output reg DE,					// DE Pin
	
	output wire[7:0] LED,
	
	
	output reg[8*513:0]	DMX_Data,
	output reg[9:0]		N_Of_Data,		// DMX 데이터의 바이트 수
	output reg				Signal_EN		// DMX 신호가 수신 중인지
);


	
	// DMX -> A Port, 8-bit, 513 addr
	// Compare -> B Port, 64-bit, 65 addr
	EBR EBR_Inst(
		.ClockA(clk),
		.ClockB(clk),
		.ResetA(~rst_n),
		.ResetB(~rst_n),
		.ClockEnA(1'b1),
		.ClockEnB(1'b1),
		
		.WrA(EBR_Wr_A),
		.AddressA(EBR_Addr_A),
		.DataInA(EBR_Data_In_A),
		
		.WrB(1'b0),	// read only
		.AddressB(EBR_Addr_B),
		.QB(EBR_QB)
	);

	// EBR control registers
	reg EBR_Wr_A;
	reg [9:0] EBR_Addr_A;
	reg [8:0] EBR_Data_In_A;
	
	reg [7:0] 	EBR_Addr_B;		// EBR Address
	wire [63:0] 	EBR_QB;		// EBR Data
	
	reg [8:0] EBR_Copy_Counter;
	integer i;

	// **DMX Timing Parameters**
    localparam BIT_TIME   = CLK_FREQ / BAUD_RATE; // 1비트 클럭 사이클 수 (250kbps 기준 4μs)
    localparam HALF_BIT_TIME  = BIT_TIME / 2;     // 중앙 샘플링용 2μs
    localparam BREAK_TIME = (CLK_FREQ / 1000000) * 88;  // BREAK 최소 88μs
    localparam MAB_TIME   = (CLK_FREQ / 1000000) * 8;   // MAB 최소 8μs
    localparam PACKET_END_TIMEOUT = (CLK_FREQ / 1000000) * 16;  // **패킷 종료 타임아웃 16μs**

    // **비트 타이머 크기 자동 계산 (? BIT_TIMER_WIDTH 선언 추가)**
    localparam integer MAX_TIME_1S = CLK_FREQ; 
    localparam integer BIT_TIMER_WIDTH = $clog2(MAX_TIME_1S); // 최소한의 비트 수 계산
	
	// **Registers (? BIT_TIMER_WIDTH 기반 레지스터 선언)**
    reg [BIT_TIMER_WIDTH-1:0] bit_timer;
    reg [BIT_TIMER_WIDTH-1:0] bit_sample_timer;
    reg [BIT_TIMER_WIDTH-1:0] break_width, mab_width;
    reg [BIT_TIMER_WIDTH-1:0] packet_timeout;  // **패킷 종료 타이머**
    reg [3:0] bit_count;
    reg [3:0] state;
	reg [4:0] byte_receive_state;
	reg [4:0] packetCopy_state;
    reg dmx_prev;
    reg start_bit_detected;
	
	// Byte 임시 저장 register
	reg [9:0] byte_received_counter_temp;
	reg [7:0] byte_received_temp;
	
	
	// Data Copy 용 wire
	reg [63:0] DMX_Data_Copy [0:64];
	assign DMX_Data = DMX_Data_Copy;
	
	 // **FSM States**
    localparam IDLE         = 0,
               BREAK        = 1,
               MAB          = 2,
               BYTE_RECEIVE = 3,
               PACKET_COPY  = 4;
			   
	// **BYTE RECEIVE FSM States**
    localparam BR_STARTBIT_CHECK = 10,
               BR_HALF_WIDTH_DELAY = 11,
               BR_8BIT_RECEIVE = 12,
               BR_STOPBITS_CHECK = 13,
               BR_NEXTBYTE_CHECK = 14;
			   

	// FSM
	always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
			state <= IDLE;
			byte_receive_state <= BR_STARTBIT_CHECK;
			
            byte_received_counter_temp <= 0;
            bit_timer <= 0;
            packet_timeout <= 0;
			
			EBR_Wr_A <= 0;
			EBR_Addr_A <= 0;
			EBR_Data_In_A <= 0;
			
			EBR_Copy_Counter <= 0;
			
			Signal_EN <= 0;
			N_Of_Data <= 0;
		end
		
		
		else begin
			dmx_prev <= DMX_Input_Signal;
			
			case (state)

                // **IDLE 상태: Break 감지 대기**
                IDLE: begin
					byte_received_counter_temp <= 0;
					EBR_Wr_A <= 0;						// EBR Write Disabled
					EBR_Addr_A <= 0;					// Address set to 0
					EBR_Data_In_A <= 0;
					
					
					// Falling Edge Detected
                    if (DMX_Input_Signal == 0 && dmx_prev == 1) begin
                        bit_timer <= 0;
                        state <= BREAK;
						byte_receive_state <= BR_STARTBIT_CHECK;
                    end
                end
				
				 // **BREAK 감지 상태**
                BREAK: begin
					// DMX 신호가 0을 유지하는 동안 시간 측정.
                    if (DMX_Input_Signal == 0) begin
                        bit_timer <= bit_timer + 1;
						// 너무 오래 0을 유지하면 Error
                        if (bit_timer > (CLK_FREQ * 1)) begin
                            state <= IDLE;
                        end
					// DMX 신호의 Rising Edge 감지.
                    end else if (DMX_Input_Signal == 1 && dmx_prev == 0) begin
                        break_width <= bit_timer;
						// Break가 최소 시간인 88us보다 크면 Pass
                        if (bit_timer >= BREAK_TIME) begin
                            state <= MAB;
                            bit_timer <= 0;
                        end 
						// Break가 88us보다 짧음. Error
						else begin
                            state <= IDLE;
                        end
                    end
                end
				
				
				// **MAB 감지 상태**
                MAB: begin
					// DMX 신호가 1을 유지 하는 동안 시간 측정
                    if (DMX_Input_Signal == 1) begin
                        bit_timer <= bit_timer + 1;
						// 너무 오래 1을 유지하면 Error
                        if (bit_timer > (CLK_FREQ * 1)) begin
                            state <= IDLE;
                        end
					// DMX 신호의 Falling Edge 감지
                    end else if (DMX_Input_Signal == 0 && dmx_prev == 1) begin
                        mab_width <= bit_timer;
						// MAB 시간이 맞으면 Pass
                        if (bit_timer >= MAB_TIME) begin
                            state <= BYTE_RECEIVE;
                            bit_timer <= 0;
                            packet_timeout <= 0;
                        end 
						// MAB 시간 안맞음 Error
						else begin
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
							if(DMX_Input_Signal == 0) begin
								byte_receive_state <= BR_HALF_WIDTH_DELAY;	// 다음 단계로
								bit_sample_timer <= HALF_BIT_TIME;			// half cycle timer 세팅
								byte_received_temp <= 0;					// 바이트 임시 저장 버퍼 clear
								
								// EBR Write Disabled
								EBR_Wr_A <= 1'b0;
							end
							// **패킷 수신 후 일정 시간 (16μs) 동안 추가 데이터 없으면 증가**
							else if (packet_timeout < PACKET_END_TIMEOUT) begin
								packet_timeout <= packet_timeout + 1;  
							end
							
							// **16μs 동안 start bit가 안옴. 패킷 수신 종료
							else begin
								
								// 수신 된 bytes가 있음
								if(byte_received_counter_temp != 0) begin
									
									// 64-bit(8바이트) 단위로 카운트 설정
									EBR_Copy_Counter <= byte_received_counter_temp / 8;

									// 만약 8바이트로 나누어 떨어지지 않으면 +1 추가
									if (byte_received_counter_temp % 8 != 0) begin
										EBR_Copy_Counter <= EBR_Copy_Counter + 1;
									end
									
									EBR_Addr_B <= 0;				// EBR Address set to 0
									state <= PACKET_COPY;			// Packet 복사로 넘어가기
								end
								
								// 수신 된 byte 없음
								else begin
									state <= IDLE;
								end
								
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
								byte_received_temp <= {DMX_Input_Signal, byte_received_temp[7:1]};  // **LSB 우선으로 첫 번째 데이터 비트 수신**
								bit_count <= bit_count + 1;
								bit_timer <= BIT_TIME;					// 4us reset
							end
							// 8-bit 수신 완료. Stop bit인지 확인 후 2번째 Stop bit Check로 넘어감
							else if(bit_timer == 0 && bit_count == 8) begin
								// first Stop bit ?
								if(DMX_Input_Signal == 1) begin
									byte_receive_state <= BR_STOPBITS_CHECK;	// stop bit 체크로 넘어감
									bit_timer <= BIT_TIME;						// 4us reset
								end
								// No Stop bit. Error
								else begin
									state <= IDLE;
								end
								
							end
							// bit timer counter decreases
							else begin
								bit_timer <= bit_timer - 1;	
							end
						end
						
						// 2nd stop bits 확인
						BR_STOPBITS_CHECK: begin
							if(bit_timer == 0) begin
								
								// 2nd stop bit
								if(DMX_Input_Signal == 1) begin
									
									// 바이트 저장
									EBR_Addr_A <= byte_received_counter_temp;								// EBR Address Set
									EBR_Data_In_A <= byte_received_temp;									// EBR Data Set
									EBR_Wr_A <= 1'b1;														// EBR Write Enable
									byte_received_counter_temp <= byte_received_counter_temp + 1;			// EBR Address Increases
									
									byte_receive_state <= BR_STARTBIT_CHECK;	// 다음 바이트 계속 수신
									
									byte_received_temp <= 0;					// 바이트 수신 버퍼 clear
								end
								
								// stop bit error
								else begin
									state <= IDLE;
								end
								
							end
							else begin
								bit_timer <= bit_timer - 1;	
							end
							
						end
					endcase
				end
				
				
				// **PACKET_COPY 상태: 유효 수신 데이터 패킷 시 업데이트**
				PACKET_COPY: begin
					
					// Copy 64-bit
					if(EBR_Copy_Counter > 0) begin
						
						DMX_Data_Copy[EBR_Copy_Counter]  <= EBR_QB[EBR_Addr_B];
						
						EBR_Addr_B <= EBR_Addr_B + 1;
						EBR_Copy_Counter <= EBR_Copy_Counter - 1;
					end
					
					// Copy Done
					else begin
						Signal_EN <= 1;  // DMX 신호 수신 완료
						N_Of_Data <= byte_received_counter_temp;	// 수신된 데이터 개수 (Start Code )
						state <= IDLE;
					end
					
					
					/*
					if ((EBR_Copy_Counter * 8) < byte_received_counter_temp) begin  // 수신된 데이터 개수보다 작은 경우만 실행
						for (i = 0; i < 8; i = i + 1) begin
							if ((EBR_Copy_Counter * 8) + i < N_Of_Data) begin
								DMX_Data[(EBR_Copy_Counter * 8) + i] <= EBR_QB[(i * 8) +: 8];
							end
						end

						// 다음 64-bit 데이터 읽기 위해 주소 증가
						EBR_Addr_B <= EBR_Addr_B + 1;

						// 카운터 증가 (다음 64-bit 블록으로 이동)
						EBR_Copy_Counter <= EBR_Copy_Counter + 1;
					end else begin
						// Copy Done
						Signal_EN <= 1;  // DMX 데이터 복사 완료 신호
						N_Of_Data <= byte_received_counter_temp;	// 수신된 데이터 개수 (Start Code )
						state <= IDLE;
					end
					*/
					
					
				end
				
			endcase
			
		end
		
	end
			

endmodule
