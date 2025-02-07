module DMX_Tx #(
    parameter CLK_FREQ = 12090000,  // 시스템 클럭 Hz (기본값)
    parameter BAUD_RATE = 250000     // DMX 송신 속도 (250kbps)
)(
    input wire clk,               // 시스템 클럭 입력
    input wire rst_n,             // Active-Low 리셋
    input wire enable,            // 송출 활성화 신호 (HIGH: 계속 송출, LOW: 현재 송출 종료 후 멈춤)
    input wire [7:0] dmx_data,    // 전송할 DMX 데이터 (1채널)
    input wire [1:0] mode_select, // DMX 모드 선택 (00: 10Hz, 01: 20Hz, 10: 30Hz, 11: 40Hz)
    output reg tx,                // RS-485 송신 신호 (DMX 데이터 송출)
    output reg busy               // 송신 중 여부 (HIGH: 송출 중, LOW: 대기)
);

    // **Baud Rate Generator (250kbps = 4µs per bit)**
    localparam integer BIT_TIME = CLK_FREQ / BAUD_RATE;  // 48 (for 12.09MHz clock)

    // **DMX Timing Constants (CLK_FREQ에 따라 자동 조정)**
    localparam integer BREAK_TIME = (CLK_FREQ / 1000000) * 180;  // BREAK 기간 (180µs)
    localparam integer MAB_TIME   = (CLK_FREQ / 1000000) * 20;   // MARK After Break (20µs)

    // **모드별 Inter-Slot Delay 설정 (주기 조절)**
    reg [15:0] inter_slot_delay;
    reg [31:0] packet_timer; // 패킷 전송 주기 타이머

    always @(*) begin
        case (mode_select)
            2'b00: inter_slot_delay = (CLK_FREQ / 1000000) * 151;  // 10Hz
            2'b01: inter_slot_delay = (CLK_FREQ / 1000000) * 53;   // 20Hz
            2'b10: inter_slot_delay = (CLK_FREQ / 1000000) * 20;   // 30Hz
            2'b11: inter_slot_delay = (CLK_FREQ / 1000000) * 4;    // 40Hz
            default: inter_slot_delay = (CLK_FREQ / 1000000) * 4;  // 기본값 40Hz
        endcase
    end

    // **DMX 패킷 송출 간격 설정 (모드별 전송 주기)**
    always @(*) begin
        case (mode_select)
            2'b00: packet_timer = CLK_FREQ / 10;   // 10Hz (100ms)
            2'b01: packet_timer = CLK_FREQ / 20;   // 20Hz (50ms)
            2'b10: packet_timer = CLK_FREQ / 30;   // 30Hz (33.3ms)
            2'b11: packet_timer = CLK_FREQ / 40;   // 40Hz (25ms)
            default: packet_timer = CLK_FREQ / 40; // 기본값 40Hz
        endcase
    end

    // **레지스터 변수 선언**
    reg [15:0] counter;
    reg [31:0] packet_counter; // 패킷 간격을 위한 타이머
    reg [5:0] state;
    reg [7:0] shift_reg;
    reg [3:0] bit_index;
    reg start_tx;

    // **enable 신호에 따라 자동 송출 제어**
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            packet_counter <= 0;
            start_tx <= 0;
        end else if (enable) begin  // enable이 HIGH일 때만 패킷 송출
            if (packet_counter >= packet_timer) begin
                start_tx <= 1; // 새로운 패킷 시작
                packet_counter <= 0;
            end else begin
                start_tx <= 0;
                packet_counter <= packet_counter + 1;
            end
        end else begin
            start_tx <= 0;
        end
    end

    // **FSM - DMX 송신 프로세스 (250kbps 비트 타이밍 포함)**
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            tx <= 1;
            busy <= 0;
            counter <= 0;
            bit_index <= 0;
            shift_reg <= 0;
        end else begin
            case (state)
                // **대기 상태 (Idle)**
                0: begin
                    if (start_tx) begin
                        state <= 1;
                        busy <= 1;
                        counter <= 0;
                    end
                end

                // **BREAK 전송**
                1: begin
                    tx <= 0;
                    if (counter < BREAK_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        state <= 2;
                    end
                end

                // **MAB 전송**
                2: begin
                    tx <= 1;
                    if (counter < MAB_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        shift_reg <= 8'h00;  // START CODE (0x00)
                        bit_index <= 0;
                        state <= 3;
                    end
                end

                // **START CODE 전송**
                3: begin
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        tx <= shift_reg[0];
                        shift_reg <= shift_reg >> 1;
                        bit_index <= bit_index + 1;
                        if (bit_index == 7) begin
                            shift_reg <= dmx_data;
                            bit_index <= 0;
                            state <= 4;
                        end
                    end
                end

                // **데이터 전송**
                4: begin
                    if (counter < BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        tx <= shift_reg[0];
                        shift_reg <= shift_reg >> 1;
                        bit_index <= bit_index + 1;
                        if (bit_index == 7) state <= 5;
                    end
                end

                // **Stop Bit (2개) 전송**
                5: begin
                    if (counter < 2 * BIT_TIME) counter <= counter + 1;
                    else begin
                        counter <= 0;
                        state <= 6;
                    end
                end

                // **Inter-Slot Delay 후 Idle 전환**
                6: begin
                    if (counter < inter_slot_delay) counter <= counter + 1;
                    else begin
                        busy <= 0;
                        state <= enable ? 0 : 7;
                    end
                end

                // **대기 상태 (Enable OFF)**
                7: begin
                    tx <= 1;
                    state <= 0;
                end

                default: state <= 0;
            endcase
        end
    end
endmodule
