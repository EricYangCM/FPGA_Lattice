
module DMX_Output_Module #(
	parameter CLK_FREQ = 12000000,  // 시스템 클럭
	parameter BAUD_RATE = 250000,    // DMX 통신 속도
	parameter DMX_BUFFER_SIZE = 513
)(
	input wire clk,
    input wire rst_n,
	
	// DMX Input A
	input wire [(8*DMX_BUFFER_SIZE)-1:0] 	DMX_Data_A,	// 출력 할 DMX Data Buffer
    input wire [9:0] N_Of_Bytes_A,   					// 송출할 데이터 개수 (1~512)
	input wire Signal_Enabled_A,						// DMX 데이터가 유효한지 (업데이트 중인건지)
	
	// DMX Input B
	input wire [(8*DMX_BUFFER_SIZE)-1:0] 	DMX_Data_B,	// 출력 할 DMX Data Buffer
    input wire [9:0] N_Of_Bytes_B,   					// 송출할 데이터 개수 (1~512)
	input wire Signal_Enabled_B,						// DMX 데이터가 유효한지 (업데이트 중인건지)
	
	
	// Control Registers
	input wire TX_EN,            					// 송출 활성화 신호 (HIGH: 계속 송출, LOW: 현재 송출 종료 후 멈춤)
	input wire DMX_SEL,								// 2개의 DMX Input 중 Select
	input wire [1:0] FREQ_MODE, 					// DMX Freq 모드 선택 (00: 10Hz, 01: 20Hz, 10: 30Hz, 11: 40Hz)
	
	output reg DE,					// DE Pin
	output reg DMX_Output_Signal,
	
	
	output wire [7:0] LED
);

	assign LED[7:0] = ~N_Of_Bytes[7:0];

	// **Baud Rate Generator (250kbps = 4μs per bit)**
    localparam integer BIT_TIME = CLK_FREQ / BAUD_RATE;  // 48 (for 12.09MHz clock)

    // **DMX Timing Constants**
	localparam integer BREAK_TIME = (CLK_FREQ / 1000000) * 100;  // BREAK 기간 (100μs)
    localparam integer MAB_TIME   = (CLK_FREQ / 1000000) * 20;   // MARK After Break (20μs)

	// Freqeuncy Mode
    reg [31:0] packet_timer;
    always @(*) begin
        case (FREQ_MODE)
            2'b00: packet_timer = CLK_FREQ / 10;   
            2'b01: packet_timer = CLK_FREQ / 20;   
            2'b10: packet_timer = CLK_FREQ / 30;   
            2'b11: packet_timer = CLK_FREQ / 40;   
            default: packet_timer = CLK_FREQ / 40;
        endcase
    end
	
	// DMX Data Mux (Read only)
	wire [8*DMX_BUFFER_SIZE:0] DMX_Data;
    wire [9:0] N_Of_Bytes;
    wire Signal_Enabled;
	
	assign DMX_Data     = (DMX_SEL) ? DMX_Data_B     : DMX_Data_A;
    assign N_Of_Bytes   = (DMX_SEL) ? N_Of_Bytes_B   : N_Of_Bytes_A;
    assign Signal_Enabled = (DMX_SEL) ? Signal_Enabled_B : Signal_Enabled_A;
	
	
	
	// **레지스터 변수 선언**
    reg [15:0] counter;		// 통신 타이밍 카운터
    reg [31:0] packet_counter;
    reg [5:0] state;
	reg [7:0] shift_reg;
    reg start_tx;
	reg [3:0] bit_index;		// 현재 tx 중인 bit index
	reg [9:0] byte_index;		// 현재 tx 된 바이트 index

    // **enable 신호에 따라 자동 송출 제어**
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			packet_counter <= 0;
			start_tx <= 0;
		end else if (TX_EN) begin
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
			// 초기화
			if (!rst_n) begin
				state <= 0;
				DMX_Output_Signal <= 1;
				counter <= 0;
			end 
			
			
			else begin
				
				case (state)
                0: begin
                    if (start_tx) begin
						state <= 1;
                        counter <= 0;
						bit_index <= 0;
						byte_index <= 0;
                    end
                end

                1: begin // **BREAK 전송**
                    DMX_Output_Signal <= 0;
                    if (counter < BREAK_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        state <= 2;
                    end
                end

                2: begin // **MAB 전송**
                    DMX_Output_Signal <= 1;
                    if (counter < MAB_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
						shift_reg <= DMX_Data[7:0];	// 첫 데이터 넣기
						byte_index <= byte_index + 1;
                        state <= 3;
                    end
                end
				

                3: begin // **Start Bit 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        DMX_Output_Signal <= 0;  // **Start Bit 추가**
                        state <= 4;
                    end
                end

                4: begin // **8-bit 데이터 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
						
						// bit data 보내기
						DMX_Output_Signal <= shift_reg[0];
                        shift_reg <= shift_reg >> 1;
						
                        bit_index <= bit_index + 1;

                        if (bit_index == 8) begin
                            bit_index <= 0;
							DMX_Output_Signal <= 1;		// set stop bit
                            state <= 5;
                        end
						
                    end
                end

                5: begin // **Stop Bit (2-bit HIGH) 전송**
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
						byte_index <= byte_index + 1;
						
						// 전송 할 byte 남음 ?
						if (byte_index < N_Of_Bytes) begin
							shift_reg <= DMX_Data[(byte_index*8) +: 8];		// shift 레지스터에 8비트 잘라서 넣기
							state <= 3;  // **Start Bit부터 다시 전송**
						// byte 전송 끝남
						end else begin
							state <= TX_EN ? 0 : 6;
						end
						
                    end
                end
				
                6: begin // **Idle 상태 (Enable OFF)**
                    DMX_Output_Signal <= 1;
                    state <= 0;
                end

                default: state <= 0;
				endcase
			
			
			end
		end
		
		
		
		
		
		
endmodule
