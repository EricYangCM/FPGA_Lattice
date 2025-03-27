module ByteReceiver #(
    parameter CLK_FREQ   = 20_000_000,
    parameter BAUD_RATE  = 250_000
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start_receive,         // 수신 시작 트리거
    input  wire DMX_Input_Signal,      // DMX 입력

    output reg        byte_ready,      // 1클럭 high, 바이트 수신 완료
    output reg [7:0]  received_byte,   // 수신된 바이트
    output reg        error,           // Stop 비트 에러 발생 시 1
    output reg        byte_done       // 일정 시간동안 새 start bit 없으면 1클럭 high
);

    localparam BIT_TIME       = CLK_FREQ / BAUD_RATE;       // 4us = 80 clk
    localparam HALF_BIT_TIME  = BIT_TIME / 2;               // 2us = 40 clk
    localparam BYTE_TIMEOUT   = (CLK_FREQ * 44) / 1_000_000; // 44us = 880 clk
    localparam TIMER_BITS     = $clog2(BYTE_TIMEOUT);

    // FSM 상태 정의
    localparam IDLE              = 0,
               START_BIT_CENTER  = 1,
               DATA_BIT_SAMPLING = 2,
               STOP_BIT_1        = 3,
               STOP_BIT_2        = 4,
               WAIT_START_BIT    = 5;

    reg [2:0] state;
    reg [TIMER_BITS-1:0] bit_timer;
    reg [TIMER_BITS-1:0] timeout_counter;
    reg [3:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            bit_timer       <= 0;
            timeout_counter <= 0;
            bit_index       <= 0;
            shift_reg       <= 0;
            received_byte   <= 0;
            byte_ready      <= 0;
            byte_done       <= 0;
            error           <= 0;
        end else begin
            byte_ready <= 0;
            byte_done  <= 0;

            case (state)

                // --------------------------
                IDLE: begin
                    if (start_receive) begin
                        bit_timer       <= HALF_BIT_TIME;
                        bit_index       <= 0;
                        timeout_counter <= 0;
                        state           <= START_BIT_CENTER;
                    end
                end

                // --------------------------
                DATA_BIT_SAMPLING: begin
                    if (bit_timer > 0) begin
                        bit_timer <= bit_timer - 1;
                    end else begin
                        shift_reg <= {DMX_Input_Signal, shift_reg[7:1]};
                        bit_index <= bit_index + 1;
                        bit_timer <= BIT_TIME;
                        timeout_counter <= 0;

                        if (bit_index == 7) begin
                            received_byte <= {DMX_Input_Signal, shift_reg[7:1]};
                            state <= STOP_BIT_1;
                        end
                    end
                end

                // --------------------------
                STOP_BIT_1: begin
                    if (bit_timer > 0) begin
                        bit_timer <= bit_timer - 1;
                    end else begin
                        if (DMX_Input_Signal == 1) begin
                            bit_timer <= BIT_TIME;
                            state <= STOP_BIT_2;
                        end else begin
                            error <= 1;
                            state <= IDLE;
                        end
						
                    end
                end

                // --------------------------
                STOP_BIT_2: begin
                    if (bit_timer > 0) begin
                        bit_timer <= bit_timer - 1;
                    end else begin
                        if (DMX_Input_Signal == 1) begin
                            byte_ready <= 1;
                            error <= 0;
                            state <= WAIT_START_BIT;
                            timeout_counter <= 0;
                        end else begin
                            error <= 1;
                            state <= IDLE;
                        end
						
                    end
                end

                // --------------------------
                WAIT_START_BIT: begin
                    if (DMX_Input_Signal == 0) begin
                        bit_timer <= HALF_BIT_TIME;
                        bit_index <= 0;
                        state <= START_BIT_CENTER;
                        timeout_counter <= 0;
                    end else if (timeout_counter < BYTE_TIMEOUT) begin
                        timeout_counter <= timeout_counter + 1;
                    end else begin
                        byte_done <= 1;
                        state <= IDLE;
                    end
                end

                // --------------------------
                START_BIT_CENTER: begin
                    if (bit_timer > 0) begin
                        bit_timer <= bit_timer - 1;
                    end else begin
                        if (DMX_Input_Signal == 0) begin
                            bit_timer <= BIT_TIME;
                            state <= DATA_BIT_SAMPLING;
                        end else begin
                            error <= 1;
                            state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule
