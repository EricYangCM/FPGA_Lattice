module ByteReceiver #(
    parameter CLK_FREQ   = 20_000_000,
    parameter BAUD_RATE  = 250_000
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start_receive,
    input  wire DMX_Input_Signal,

    output reg        byte_ready,
    output reg [7:0]  received_byte,
    output reg        error,
    output reg        byte_done
);

    localparam BIT_TIME       = CLK_FREQ / BAUD_RATE;       // 4us = 80 clk
    localparam HALF_BIT_TIME  = BIT_TIME / 2;
    localparam BYTE_TIMEOUT   = (CLK_FREQ * 44) / 1_000_000;
    localparam TIMER_BITS     = $clog2(BYTE_TIMEOUT);

    localparam IDLE              = 0,
               START_BIT_CENTER  = 1,
               DATA_BIT_SAMPLING = 2,
               STOP_BIT_1        = 3,
               STOP_BIT_2        = 4,
               BYTE_READY_DELAY  = 5,
               WAIT_START_BIT    = 6;

    reg [2:0] state;
    reg [TIMER_BITS-1:0] bit_timer;
    reg [TIMER_BITS-1:0] timeout_counter;
    reg [3:0] bit_index;
    reg [7:0] shift_reg;

    reg [2:0] byte_ready_cnt;

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
            byte_ready_cnt  <= 0;
        end else begin
            byte_ready <= 0;
            byte_done  <= 0;

            case (state)
                IDLE: begin
                    if (start_receive) begin
                        bit_timer       <= HALF_BIT_TIME;
                        bit_index       <= 0;
                        timeout_counter <= 0;
                        state           <= START_BIT_CENTER;
                    end
                end

                START_BIT_CENTER: begin
                    if (bit_timer > 0)
                        bit_timer <= bit_timer - 1;
                    else if (DMX_Input_Signal == 0) begin
                        bit_timer <= BIT_TIME;
                        state <= DATA_BIT_SAMPLING;
                    end else begin
                        error <= 1;
                        state <= IDLE;
                    end
                end

                DATA_BIT_SAMPLING: begin
                    if (bit_timer > 0)
                        bit_timer <= bit_timer - 1;
                    else begin
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

                STOP_BIT_1: begin
                    if (bit_timer > 0)
                        bit_timer <= bit_timer - 1;
                    else if (DMX_Input_Signal == 1) begin
                        bit_timer <= BIT_TIME;
                        state <= STOP_BIT_2;
                    end else begin
                        error <= 1;
                        state <= IDLE;
                    end
                end

                STOP_BIT_2: begin
                    if (bit_timer > 0)
                        bit_timer <= bit_timer - 1;
                    else if (DMX_Input_Signal == 1) begin
                        error <= 0;
                        byte_ready_cnt <= 3;  // << 안전하게 3클럭 유지
                        state <= BYTE_READY_DELAY;
                    end else begin
                        error <= 1;
                        state <= IDLE;
                    end
                end

                BYTE_READY_DELAY: begin
                    byte_ready <= 1;
                    if (byte_ready_cnt == 0) begin
                        state <= WAIT_START_BIT;
                        timeout_counter <= 0;
                    end else begin
                        byte_ready_cnt <= byte_ready_cnt - 1;
                    end
                end

                WAIT_START_BIT: begin
                    if (DMX_Input_Signal == 0) begin
                        bit_timer <= HALF_BIT_TIME;
                        bit_index <= 0;
                        state <= START_BIT_CENTER;
                        timeout_counter <= 0;
                    end else if (timeout_counter < BYTE_TIMEOUT)
                        timeout_counter <= timeout_counter + 1;
                    else begin
                        byte_done <= 1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
