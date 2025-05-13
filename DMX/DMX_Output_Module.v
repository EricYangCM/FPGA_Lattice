module DMX_Output_Module #(
    parameter CLK_FREQ = 20_000_000,
    parameter BAUD_RATE = 250_000,
	parameter WAIT_CYCLES = 10  // 원하는 딜레이 사이클 수 (20MHz 기준 4사이클이면 0.2us 정도)
)(
    input wire clk,
    input wire rst_n,

    // EBR 포트 B (외부 접근용: Write Only)
    input  wire [9:0]  EBR_Addr_B,
    input  wire [7:0] EBR_DataIn_B,
	input wire EBR_WrB,

    input wire [9:0] Channel_Count,     // 수신할 채널 개수
    input wire Enable,                  // 송출 Enable
    input wire [1:0] FREQ_MODE,         // 송출 주파수 모드 (00:10Hz ~ 11:40Hz)

    output reg DE,
    output reg DMX_Output_Signal
);

    localparam BIT_TIME    = CLK_FREQ / BAUD_RATE;
    localparam BREAK_TIME  = (CLK_FREQ / 1_000_000) * 100;  // 100us
    localparam MAB_TIME    = (CLK_FREQ / 1_000_000) * 20;   // 20us

    // 송출 주기 타이머 설정
    reg [31:0] packet_timer;
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			packet_timer <= CLK_FREQ / 40;
		end else begin
			case (FREQ_MODE)
				2'b00: packet_timer <= CLK_FREQ / 10;
				2'b01: packet_timer <= CLK_FREQ / 20;
				2'b10: packet_timer <= CLK_FREQ / 30;
				2'b11: packet_timer <= CLK_FREQ / 40;
				default: packet_timer <= CLK_FREQ / 40;
			endcase
		end
	end

    reg [31:0] packet_counter;
    reg start_tx;

    // Enable 기반 송출 트리거
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            packet_counter <= 0;
            start_tx <= 0;
        end else if (Enable) begin
            if (packet_counter >= packet_timer) begin
                packet_counter <= 0;
                start_tx <= 1;
            end else begin
                packet_counter <= packet_counter + 1;
                start_tx <= 0;
            end
        end else begin
            packet_counter <= 0;
            start_tx <= 0;
        end
    end

    // (Port A: Read / Port B: Write)
    reg  [9:0]  EBR_Addr_A;
    wire [7:0]  EBR_QA;


    EBR EBR_Inst (
        .ClockA(clk), .ClockB(clk),
        .ClockEnA(1'b1), .ClockEnB(1'b1),
        .ResetA(~rst_n), .ResetB(~rst_n),

        // Port A (내부 Read)
        .AddressA(EBR_Addr_A),
        .WrA(1'b0),	// read
        .QA(EBR_QA),

        // Port B (외부 Write)
        .AddressB(EBR_Addr_B),
        .DataInB(EBR_DataIn_B),
        .WrB(EBR_WrB)	// write
    );

    //  FSM 정의
	localparam IDLE = 0, BREAK = 1, MAB = 2,
           WAIT_READ = 3,
           START_BIT = 4, DATA_BITS = 5,
           LAST_BIT_HOLD = 6, STOP_BITS = 7;

    reg [3:0] state;
	reg [4:0] wait_counter;  // EBR wait 용 카운터
    reg [15:0] counter;
    reg [3:0] bit_index;
    reg [9:0] byte_index;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            counter <= 0;
            bit_index <= 0;
            byte_index <= 0;
            DE <= 1;
            DMX_Output_Signal <= 1;
            EBR_Addr_A <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_tx) begin
                        byte_index <= 0;
                        EBR_Addr_A <= 0;
                        counter <= 0;
                        DMX_Output_Signal <= 0;
                        state <= BREAK;
                    end
                end

                BREAK: begin
                    if (counter < BREAK_TIME)
                        counter <= counter + 1;
                    else begin
                        counter <= 0;
                        DMX_Output_Signal <= 1;
                        state <= MAB;
                    end
                end

                MAB: begin
                    if (counter < MAB_TIME)
                        counter <= counter + 1;
                    else begin
						wait_counter <= 0;
                        state <= WAIT_READ;
                    end
                end 
				
				WAIT_READ: begin
					if (wait_counter == 0) begin
						EBR_Addr_A <= byte_index;  // 주소 설정 (처음 1회만)
					end
					
					if (wait_counter < WAIT_CYCLES - 1) begin
						wait_counter <= wait_counter + 1;
					end
					else begin
						counter <= 0;
                        bit_index <= 0;
						DMX_Output_Signal <= 0;  // Start Bit
						shift_reg <= EBR_QA;	  // Set Data
						state <= START_BIT;
					end
				end

				START_BIT: begin
					if (counter < BIT_TIME) begin
						counter <= counter + 1;
						DMX_Output_Signal <= 0; // Start Bit 구간 유지
						
					end else begin
						counter <= 0;
						DMX_Output_Signal <= shift_reg[0]; // 첫 번째 데이터 비트 출력
						shift_reg <= shift_reg >> 1;
						bit_index <= 1;
						state <= DATA_BITS;
					end
				end

				DATA_BITS: begin
					if (counter < BIT_TIME)
						counter <= counter + 1;
					else begin
						counter <= 0;
						DMX_Output_Signal <= shift_reg[0];
						shift_reg <= shift_reg >> 1;
						bit_index <= bit_index + 1;

						if (bit_index == 7) begin
							// 마지막 비트 출력했으므로 다음 상태로 넘어가지 않고
							// 다음 상태로 넘어가기 전에 1비트 시간만큼 그대로 유지
							state <= LAST_BIT_HOLD;
						end
					end
				end
				
				LAST_BIT_HOLD: begin
					if (counter < BIT_TIME) begin
						counter <= counter + 1;
						// 마지막 비트 유지, DMX_Output_Signal 그대로 유지됨
					end else begin
						counter <= 0;
						EBR_Addr_A <= byte_index + 1;
						byte_index <= byte_index + 1;
						state <= STOP_BITS;
					end
				end

				STOP_BITS: begin
					if (counter < (2 * BIT_TIME)) begin
						DMX_Output_Signal <= 1;  // stop bit는 항상 high
						counter <= counter + 1;
					end else begin
						counter <= 0;
						if (byte_index < Channel_Count) begin
							state <= WAIT_READ;
							wait_counter <= 0;
						end
						else begin
							state <= IDLE;
						end
					end
				end


                default: state <= IDLE;
            endcase
        end
    end

endmodule
