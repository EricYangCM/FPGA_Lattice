module DMX_Input_Module #(
    parameter CLK_FREQ = 12000000,  // 시스템 클럭
    parameter BAUD_RATE = 250000,   // DMX 통신 속도
    parameter DMX_BUFFER_SIZE = 513
)(
    input wire clk,
    input wire rst_n,
    input wire DMX_Input_Signal,  // DMX 입력 신호 핀

    output reg DE,                // DE Pin
    output reg [8 * DMX_BUFFER_SIZE:0] DMX_Data,
    output reg [9:0] N_Of_Data,    // DMX 데이터의 바이트 수 (Start Code 제외)
    output reg Signal_EN           // DMX 신호가 수신 중인지
);

    // DMX -> A Port, 8-bit, 513 addr
    // Compare -> B Port, 64-bit, 65 addr
    EBR EBR_Inst (
        .ClockA(clk),
        .ClockB(clk),
        .ResetA(~rst_n),
        .ResetB(~rst_n),
        .ClockEnA(1'b1),
        .ClockEnB(1'b1),
        .WrA(EBR_Wr_A),
        .AddressA(EBR_Addr_A),
        .DataInA(EBR_Data_In_A),
        .WrB(1'b0),  // read only
        .AddressB(EBR_Addr_B),
        .QB(EBR_QB)
    );

    // **DMX Timing Parameters**
    localparam BIT_TIME            = CLK_FREQ / BAUD_RATE;          // 1비트 클럭 사이클 수 (250kbps 기준 4μs)
    localparam HALF_BIT_TIME       = BIT_TIME / 2;                  // 중앙 샘플링용 2μs
    localparam BREAK_TIME          = (CLK_FREQ / 1000000) * 88;     // BREAK 최소 88μs
    localparam MAB_TIME            = (CLK_FREQ / 1000000) * 8;      // MAB 최소 8μs
    localparam PACKET_END_TIMEOUT  = (CLK_FREQ / 1000000) * 16;     // 패킷 종료 타임아웃 16μs

    // **비트 타이머 크기 자동 계산**
    localparam integer MAX_TIME_1S = CLK_FREQ;
    localparam integer BIT_TIMER_WIDTH = $clog2(MAX_TIME_1S); // 최소한의 비트 수 계산

    // **Registers (BIT_TIMER_WIDTH 기반 레지스터 선언)**
    reg [BIT_TIMER_WIDTH-1:0] bit_timer;
    reg [BIT_TIMER_WIDTH-1:0] bit_sample_timer;
    reg [BIT_TIMER_WIDTH-1:0] break_width, mab_width;
    reg [BIT_TIMER_WIDTH-1:0] packet_timeout;          // 패킷 종료 타이머
    reg [BIT_TIMER_WIDTH-1:0] new_packet_rx_timeout;   // 새로운 패킷 수신 타임아웃 1sec

    reg [3:0] bit_count;
    reg [3:0] state;
    reg [4:0] byte_receive_state;
    reg [4:0] packetCopy_state;
    reg dmx_prev;
    reg start_bit_detected;

    // Byte 임시 저장 register
    reg [9:0] byte_received_counter_temp;
    reg [7:0] byte_received_temp;

    // **FSM States**
    localparam IDLE         = 0,
               BREAK        = 1,
               MAB          = 2,
               BYTE_RECEIVE = 3;

    // **BYTE RECEIVE FSM States**
    localparam BR_STARTBIT_CHECK   = 10,
               BR_HALF_WIDTH_DELAY = 11,
               BR_8BIT_RECEIVE     = 12,
               BR_STOPBITS_CHECK   = 13,
               BR_NEXTBYTE_CHECK   = 14;

    // FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            byte_receive_state <= BR_STARTBIT_CHECK;
            byte_received_counter_temp <= 0;
            bit_timer <= 0;
            packet_timeout <= 0;
            new_packet_rx_timeout <= 0;
            Signal_EN <= 0;
            N_Of_Data <= 0;
        end else begin
            dmx_prev <= DMX_Input_Signal;

            // New Packet Timeout Counter
            if (new_packet_rx_timeout < CLK_FREQ) begin
                new_packet_rx_timeout <= new_packet_rx_timeout + 1;
            end else begin
                // New Packet Timeout. Clear Signal_EN
                Signal_EN <= 0;
                new_packet_rx_timeout <= 0;
            end

            // FSM
            case (state)
                // **IDLE 상태: Break 감지 대기**
                IDLE: begin
                    byte_received_counter_temp <= 0;
                    if (DMX_Input_Signal == 0 && dmx_prev == 1) begin
                        bit_timer <= 0;
                        state <= BREAK;
                        byte_receive_state <= BR_STARTBIT_CHECK;
                    end
                end

                // **BREAK 감지 상태**
                BREAK: begin
                    if (DMX_Input_Signal == 0) begin
                        bit_timer <= bit_timer + 1;
                        if (bit_timer > CLK_FREQ * 1) begin
                            state <= IDLE;
                        end
                    end else if (DMX_Input_Signal == 1 && dmx_prev == 0) begin
                        break_width <= bit_timer;
                        state <= (bit_timer >= BREAK_TIME) ? MAB : IDLE;
                        bit_timer <= 0;
                    end
                end

                // **MAB 감지 상태**
                MAB: begin
                    if (DMX_Input_Signal == 1) begin
                        bit_timer <= bit_timer + 1;
                        if (bit_timer > CLK_FREQ * 1) begin
                            state <= IDLE;
                        end
                    end else if (DMX_Input_Signal == 0 && dmx_prev == 1) begin
                        mab_width <= bit_timer;
                        state <= (bit_timer >= MAB_TIME) ? BYTE_RECEIVE : IDLE;
                        bit_timer <= 0;
                        packet_timeout <= 0;
                    end
                end

                // **BYTE_RECEIVE: Start Code 및 데이터 수신**
                BYTE_RECEIVE: begin
                    case (byte_receive_state)
                        BR_STARTBIT_CHECK: begin
                            if (DMX_Input_Signal == 0) begin
                                byte_receive_state <= BR_HALF_WIDTH_DELAY;
                                bit_sample_timer <= HALF_BIT_TIME;
                                byte_received_temp <= 0;
                            end else if (packet_timeout >= PACKET_END_TIMEOUT) begin
                                Signal_EN <= (byte_received_counter_temp != 0);
                                new_packet_rx_timeout <= 0;
                                N_Of_Data <= byte_received_counter_temp;
                                state <= IDLE;
                            end else begin
                                packet_timeout <= packet_timeout + 1;
                            end
                        end

                        BR_HALF_WIDTH_DELAY: begin
                            if (bit_sample_timer > 0) begin
                                bit_sample_timer <= bit_sample_timer - 1;
                            end else begin
                                byte_receive_state <= BR_8BIT_RECEIVE;
                                bit_timer <= BIT_TIME;
                                bit_count <= 0;
                            end
                        end

                        BR_8BIT_RECEIVE: begin
                            if (bit_timer == 0 && bit_count < 8) begin
                                byte_received_temp <= {DMX_Input_Signal, byte_received_temp[7:1]};
                                bit_count <= bit_count + 1;
                                bit_timer <= BIT_TIME;
                            end else if (bit_timer == 0 && bit_count == 8) begin
                                byte_receive_state <= (DMX_Input_Signal == 1) ? BR_STOPBITS_CHECK : IDLE;
                                bit_timer <= BIT_TIME;
                            end else begin
                                bit_timer <= bit_timer - 1;
                            end
                        end

                        BR_STOPBITS_CHECK: begin
                            if (bit_timer == 0) begin
                                if (DMX_Input_Signal == 1) begin
                                    DMX_Data[(byte_received_counter_temp * 8) +: 8] <= byte_received_temp;
                                    byte_received_counter_temp <= byte_received_counter_temp + 1;
                                    byte_receive_state <= BR_STARTBIT_CHECK;
                                end else begin
                                    state <= IDLE;
                                end
                            end else begin
                                bit_timer <= bit_timer - 1;
                            end
                        end
                    endcase
                end
            endcase
        end
    end
endmodule
