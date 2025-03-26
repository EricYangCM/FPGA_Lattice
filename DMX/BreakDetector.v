module BreakDetector #(
    parameter CLK_FREQ = 20_000_000,
    parameter MIN_WIDTH_US = 88,      // 최소 88us
    parameter MAX_WIDTH_MS = 1000     // 최대 1000ms (1초)
)(
    input  wire clk,
    input  wire rst_n,
    input  wire signal_in,
    output reg  valid_pulse
);

    localparam integer MIN_CYCLES = (CLK_FREQ / 1_000_000) * MIN_WIDTH_US; // us -> clk 변환
    localparam integer MAX_CYCLES = (CLK_FREQ / 1_000) * MAX_WIDTH_MS;     // ms -> clk 변환

    reg signal_sync_0, signal_sync_1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            signal_sync_0 <= 1'b1;
            signal_sync_1 <= 1'b1;
        end else begin
            signal_sync_0 <= signal_in;
            signal_sync_1 <= signal_sync_0;
        end
    end

    wire signal_falling = (signal_sync_1 == 1'b1) && (signal_sync_0 == 1'b0);
    wire signal_rising  = (signal_sync_1 == 1'b0) && (signal_sync_0 == 1'b1);

    reg [31:0] pulse_counter;
    reg        counting;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_counter <= 0;
            counting      <= 0;
            valid_pulse   <= 0;
        end else begin
            valid_pulse <= 0;

            if (signal_falling) begin
                counting <= 1;
                pulse_counter <= 0;
            end else if (counting) begin
                if (signal_sync_1 == 1'b0) begin
                    pulse_counter <= pulse_counter + 1;
                end else if (signal_rising) begin
                    counting <= 0;
                    if (pulse_counter >= MIN_CYCLES && pulse_counter <= MAX_CYCLES) begin
                        valid_pulse <= 1;
                    end
                end
            end
        end
    end
endmodule
