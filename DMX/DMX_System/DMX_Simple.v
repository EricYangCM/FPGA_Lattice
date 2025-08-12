// ============================================================
// DMX_Simple (Final, fixed VERI-1380)
//  - UART(8N1) + ASCII 파서 + 4채널 EBR Write MUX (단일 모듈)
//  - Frame: '$' + port('0'..'3') + ch('001'..'512') + dim('000'..'255')
//  - 유효 시 EBR(B)에 (addr=STARTCODE_OFFSET + ch, data=dim) 1클럭 write
// ============================================================
module DMX_Simple #(
    parameter CLK_FREQ         = 20_000_000,
    parameter UART_BAUD        = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,

    output wire DMX0_DE, output wire DMX0_TX,
    output wire DMX1_DE, output wire DMX1_TX,
    output wire DMX2_DE, output wire DMX2_TX,
    output wire DMX3_DE, output wire DMX3_TX
);

    // ---------------- UART 수신기 (8N1, LSB→MSB 자리지정) ----------------
    localparam integer DIV = CLK_FREQ / UART_BAUD;
    localparam integer MID = DIV/2;

    reg [15:0] u_cnt;
    reg [3:0]  u_bitn;
    reg        u_busy;
    reg        rx_d, rx_dd;

    reg [7:0]  u_data;     // 수신 바이트
    reg        u_valid;    // 1클럭 유효

    // 2단 동기화
    always @(posedge clk) begin
        rx_d  <= uart_rx;
        rx_dd <= rx_d;
    end

    // ---------------- 파서 FSM ----------------
    localparam S_WAIT=0, S_PORT=1, S_CH2=2, S_CH1=3, S_CH0=4, S_D2=5, S_D1=6, S_D0=7, S_WRITE=8;
    reg [3:0] st;

    reg [1:0] port_sel;
    reg [3:0] d_ch2, d_ch1;  // ch 상위 두 자리
    reg [3:0] d_d2,  d_d1;   // dim 상위 두 자리

    // 자리 계산은 넉넉히(0~999 커버)
    reg [11:0] ch_calc, dim_calc;

    // lookahead: S_WRITE 1클럭 동안 들어온 '$' 표시
    reg        la_dollar;

    // EBR PortB write 신호
    reg        wr_pulse;       // 1클럭
    reg [1:0]  wr_port;
    reg [9:0]  wr_addr;        // 0..1023 가정(EBR 폭에 맞게)
    reg [7:0]  wr_data;

    // digit 변환 함수
    function [3:0] ascii_to_digit;
        input [7:0] a;
        begin
            if (a >= "0" && a <= "9") ascii_to_digit = a - "0";
            else                       ascii_to_digit = 4'd15;
        end
    endfunction

    // 현재 u_data를 즉시 digit으로 쓸 수 있게 공용 wire
    wire [3:0] digit_u = ascii_to_digit(u_data);

    // ===================== 통합 always =====================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            // UART
            u_cnt<=0; u_bitn<=0; u_busy<=0; u_valid<=0; u_data<=0;
            // Parser
            st<=S_WAIT; la_dollar<=1'b0;
            d_ch2<=0; d_ch1<=0; d_d2<=0; d_d1<=0;
            ch_calc<=0; dim_calc<=0;
            wr_pulse<=1'b0; wr_port<=0; wr_addr<=0; wr_data<=0;
        end else begin
            // 기본값
            u_valid  <= 1'b0;
            wr_pulse <= 1'b0;

            // --------- UART 비트 샘플링 ---------
            if (!u_busy) begin
                if (rx_dd==1'b0) begin
                    u_busy <= 1'b1;
                    u_cnt  <= MID;
                    u_bitn <= 4'd0;
                end
            end else begin
                if (u_cnt==DIV-1) begin
                    u_cnt  <= 0;
                    u_bitn <= u_bitn + 1'b1;
                    case(u_bitn)
                        0: ; // start
                        1: u_data[0] <= rx_dd;
                        2: u_data[1] <= rx_dd;
                        3: u_data[2] <= rx_dd;
                        4: u_data[3] <= rx_dd;
                        5: u_data[4] <= rx_dd;
                        6: u_data[5] <= rx_dd;
                        7: u_data[6] <= rx_dd;
                        8: u_data[7] <= rx_dd;
                        9: begin
                            u_busy  <= 1'b0;
                            u_valid <= 1'b1;
                        end
                    endcase
                end else begin
                    u_cnt <= u_cnt + 1'b1;
                end
            end

            // --------- lookahead: S_WRITE 동안 들어온 '$' 표시 ---------
            if (u_valid && st==S_WRITE && u_data==8'h24) begin
                la_dollar <= 1'b1;
            end

            // --------- 파서 FSM ---------
            case (st)
                S_WAIT: begin
                    if (la_dollar) begin
                        la_dollar <= 1'b0;
                        st <= S_PORT;
                    end else if (u_valid) begin
                        if (u_data == 8'h24) st <= S_PORT; // '$'
                    end
                end

                S_PORT: begin
                    if (u_valid) begin
                        if (u_data>="0" && u_data<="3") begin
                            port_sel <= u_data - "0";
                            st <= S_CH2;
                        end else st <= S_WAIT;
                    end
                end

                // ch[2] (백의 자리)
                S_CH2: if (u_valid) begin
                    d_ch2 <= digit_u;
                    st    <= (digit_u != 4'd15) ? S_CH1 : S_WAIT;
                end

                // ch[1] (십의 자리)
                S_CH1: if (u_valid) begin
                    d_ch1 <= digit_u;
                    st    <= (digit_u != 4'd15) ? S_CH0 : S_WAIT;
                end

                // ch[0] (일의 자리) → **즉시 계산**
                S_CH0: if (u_valid) begin
                    if (digit_u != 4'd15) begin
                        ch_calc <= (d_ch2 * 12'd100) + (d_ch1 * 12'd10) + digit_u; // 1..512
                        st <= S_D2;
                    end else st <= S_WAIT;
                end

                // dim[2]
                S_D2: if (u_valid) begin
                    d_d2 <= digit_u;
                    st   <= (digit_u != 4'd15) ? S_D1 : S_WAIT;
                end

                // dim[1]
                S_D1: if (u_valid) begin
                    d_d1 <= digit_u;
                    st   <= (digit_u != 4'd15) ? S_D0 : S_WAIT;
                end

                // dim[0] → **즉시 계산**
                S_D0: if (u_valid) begin
                    if (digit_u != 4'd15) begin
                        dim_calc <= (d_d2 * 12'd100) + (d_d1 * 12'd10) + digit_u; // 0..255
                        st <= S_WRITE;
                    end else st <= S_WAIT;
                end

                // 쓰기: 스타트코드 0x00은 EBR[0], 채널1은 EBR[1]
                S_WRITE: begin
                    if (ch_calc >= 12'd1 && ch_calc <= 12'd512 &&
                        dim_calc <= 12'd255) begin
                        wr_port  <= port_sel;
                        wr_addr  <= ch_calc;
                        wr_data  <= dim_calc[7:0];
                        wr_pulse <= 1'b1;                        // 1클럭 write
                    end
                    if (la_dollar) begin
                        la_dollar <= 1'b0; st <= S_PORT;
                    end else begin
                        st <= S_WAIT;
                    end
                end
            endcase
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
    localparam [1:0] FREQ_40HZ = 2'b11;
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
