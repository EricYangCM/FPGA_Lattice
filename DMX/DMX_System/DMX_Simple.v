
// ============================================================
// DMX_Simple : UART 수신 + ASCII 파서 + 4채널 EBR Write MUX
//  - Frame: '$' + port('0'..'3') + ch('001'..'512') + dim('000'..'255')
//  - 유효하면 선택 포트의 EBR PortB에 (addr=ch-1, data=dim) 1클럭 write
//  - DMX_Output_Module은 외부 파일 그대로 사용
// ============================================================
module DMX_Simple #(
    parameter CLK_FREQ   = 20_000_000,
    parameter UART_BAUD  = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,

    output wire DMX0_DE, output wire DMX0_TX,
    output wire DMX1_DE, output wire DMX1_TX,
    output wire DMX2_DE, output wire DMX2_TX,
    output wire DMX3_DE, output wire DMX3_TX
);

    // ---------------- UART RX (8N1) ----------------
    wire       rx_valid;
    wire [7:0] rx_byte;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(UART_BAUD)) U_RX (
        .clk(clk), .rst_n(rst_n),
        .rx(uart_rx),
        .data_out(rx_byte), .data_valid(rx_valid)
    );

    // ---------------- 파서 상태 ----------------
    localparam S_WAIT = 0, S_PORT = 1, S_CH2=2, S_CH1=3, S_CH0=4, S_D2=5, S_D1=6, S_D0=7, S_WRITE=8;
    reg [3:0] st;

    // 수집 버퍼(ASCII → digit)
    reg [3:0] d_ch2, d_ch1, d_ch0;  // 0~9
    reg [3:0] d_dim2, d_dim1, d_dim0;
    reg [1:0] port_sel;             // 0~3

    // 정수값
    reg [9:0] ch_val;               // 1~512
    reg [7:0] dim_val;              // 0~255

    // ---------------- ASCII → digit helper ----------------
    function [3:0] ascii_to_digit;
        input [7:0] a;
        begin
            if (a >= 8'd48 && a <= 8'd57) ascii_to_digit = a - 8'd48; // '0'..'9'
            else                           ascii_to_digit = 4'd15;     // invalid
        end
    endfunction

    // ---------------- 파서 FSM ----------------
    // wr 펄스는 1클럭
    reg        wr_pulse;
    reg [9:0]  wr_addr;
    reg [7:0]  wr_data;
    reg [1:0]  wr_port;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            st <= S_WAIT;
            wr_pulse <= 1'b0;
            wr_addr <= 10'd0;
            wr_data <= 8'd0;
            wr_port <= 2'd0;
        end else begin
            wr_pulse <= 1'b0; // 기본값

            if (rx_valid) begin
                case (st)
                    S_WAIT: begin
                        if (rx_byte == 8'h24) st <= S_PORT; // '$'
                        else st <= S_WAIT;                  // 그 외는 모두 무시
                    end
                    S_PORT: begin
                        // '0'~'3'만 허용
                        if (rx_byte >= "0" && rx_byte <= "3") begin
                            port_sel <= rx_byte - "0";
                            st <= S_CH2;
                        end else begin
                            st <= S_WAIT; // 무효 포트 → 프레임 폐기
                        end
                    end
                    S_CH2: begin
                        d_ch2 <= ascii_to_digit(rx_byte);
                        st    <= (ascii_to_digit(rx_byte) != 4'd15) ? S_CH1 : S_WAIT;
                    end
                    S_CH1: begin
                        d_ch1 <= ascii_to_digit(rx_byte);
                        st    <= (ascii_to_digit(rx_byte) != 4'd15) ? S_CH0 : S_WAIT;
                    end
                    S_CH0: begin
                        d_ch0 <= ascii_to_digit(rx_byte);
                        st    <= (ascii_to_digit(rx_byte) != 4'd15) ? S_D2 : S_WAIT;
                    end
                    S_D2: begin
                        d_dim2 <= ascii_to_digit(rx_byte);
                        st     <= (ascii_to_digit(rx_byte) != 4'd15) ? S_D1 : S_WAIT;
                    end
                    S_D1: begin
                        d_dim1 <= ascii_to_digit(rx_byte);
                        st     <= (ascii_to_digit(rx_byte) != 4'd15) ? S_D0 : S_WAIT;
                    end
                    S_D0: begin
                        d_dim0 <= ascii_to_digit(rx_byte);
                        if (ascii_to_digit(rx_byte) != 4'd15) begin
                            // 여기서 범위 계산/검증
                            // ch = d2*100 + d1*10 + d0
                            ch_val  <= (d_ch2*10'd100) + (d_ch1*10'd10) + d_ch0;
                            // dim = d2*100 + d1*10 + d0 (0~255로 클램프 대신 유효성 체크)
                            dim_val <= (d_dim2*8'd100) + (d_dim1*8'd10) + d_dim0;
                            st <= S_WRITE;
                        end else begin
                            st <= S_WAIT;
                        end
                    end
                    S_WRITE: begin
                        // 채널 001~512, 디밍 000~255만 허용
                        if (ch_val >= 10'd1 && ch_val <= 10'd512 &&
                            dim_val <= 8'd255) begin
                            wr_addr  <= ch_val - 10'd1; // 0~511
                            wr_data  <= dim_val;
                            wr_port  <= port_sel;
                            wr_pulse <= 1'b1;           // 1클럭 write
                        end
                        st <= S_WAIT; // 한 프레임 처리 후 대기
                    end
                    default: st <= S_WAIT;
                endcase
            end
        end
    end

    // ---------------- 포트별 EBR PortB 라우팅 ----------------
    wire [9:0] addrB [0:3];
    wire [7:0] dataB [0:3];
    wire       wrB   [0:3];

    genvar i;
    generate for (i=0; i<4; i=i+1) begin : G_MUX
        assign addrB[i] = wr_addr;
        assign dataB[i] = wr_data;
        assign wrB[i]   = wr_pulse && (wr_port == i[1:0]);
    end endgenerate

    // ---------------- DMX 출력 모듈 4개 ----------------
    localparam [1:0] FREQ_40HZ = 2'b11;  // 사용자 요청: 주파수 모드 3
    localparam [9:0] CH_COUNT  = 10'd512;

    DMX_Output_Module #(.CLK_FREQ(CLK_FREQ)) U_DMX0 (
        .clk(clk), .rst_n(rst_n),
        .EBR_Addr_B(addrB[0]), .EBR_DataIn_B(dataB[0]), .EBR_WrB(wrB[0]),
        .Channel_Count(CH_COUNT), .Enable(1'b1), .FREQ_MODE(FREQ_40HZ),
        .DE(DMX0_DE), .DMX_Output_Signal(DMX0_TX)
    );

    DMX_Output_Module #(.CLK_FREQ(CLK_FREQ)) U_DMX1 (
        .clk(clk), .rst_n(rst_n),
        .EBR_Addr_B(addrB[1]), .EBR_DataIn_B(dataB[1]), .EBR_WrB(wrB[1]),
        .Channel_Count(CH_COUNT), .Enable(1'b1), .FREQ_MODE(FREQ_40HZ),
        .DE(DMX1_DE), .DMX_Output_Signal(DMX1_TX)
    );

    DMX_Output_Module #(.CLK_FREQ(CLK_FREQ)) U_DMX2 (
        .clk(clk), .rst_n(rst_n),
        .EBR_Addr_B(addrB[2]), .EBR_DataIn_B(dataB[2]), .EBR_WrB(wrB[2]),
        .Channel_Count(CH_COUNT), .Enable(1'b1), .FREQ_MODE(FREQ_40HZ),
        .DE(DMX2_DE), .DMX_Output_Signal(DMX2_TX)
    );

    DMX_Output_Module #(.CLK_FREQ(CLK_FREQ)) U_DMX3 (
        .clk(clk), .rst_n(rst_n),
        .EBR_Addr_B(addrB[3]), .EBR_DataIn_B(dataB[3]), .EBR_WrB(wrB[3]),
        .Channel_Count(CH_COUNT), .Enable(1'b1), .FREQ_MODE(FREQ_40HZ),
        .DE(DMX3_DE), .DMX_Output_Signal(DMX3_TX)
    );

endmodule


// ------------------------------------------------------------
// 간단한 UART RX (8N1) - Hub 내부 전용
// ------------------------------------------------------------
module uart_rx #(
    parameter CLK_FREQ = 20_000_000,
    parameter BAUD     = 115200
)(
    input  wire clk, input wire rst_n,
    input  wire rx,
    output reg  [7:0] data_out,
    output reg        data_valid
);
    localparam integer DIV = CLK_FREQ / BAUD;
    localparam integer MID = DIV/2;

    reg [15:0] cnt; reg [3:0] bitn; reg busy;
    reg rx_d, rx_dd;
    always @(posedge clk) begin rx_d<=rx; rx_dd<=rx_d; end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt<=0; bitn<=0; busy<=0; data_valid<=0; data_out<=0;
        end else begin
            data_valid<=0;
            if(!busy) begin
                if(rx_dd==1'b0) begin busy<=1; cnt<=MID; bitn<=0; end
            end else begin
                if(cnt==DIV-1) begin
                    cnt<=0;
                    bitn<=bitn+1;
                    case(bitn)
                        0: ; // start
                        1,2,3,4,5,6,7,8: data_out <= {rx_dd, data_out[7:1]};
                        9: begin busy<=0; data_valid<=1; end // stop
                    endcase
                end else cnt<=cnt+1;
            end
        end
    end
endmodule



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
