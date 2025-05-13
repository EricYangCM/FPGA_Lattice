module BreakValidator #(
    parameter CLK_FREQ = 20_000_000,
    parameter MIN_WIDTH_US = 88,      // ÃÖ¼Ò 88us
    parameter MAX_WIDTH_MS = 1000     // ÃÖ´ë 1000ms (1ÃÊ)
)(
    input  wire clk,
    input  wire rst_n,
    input  wire signal_in,
    output reg  valid_pulse
);

    localparam integer MIN_CYCLES = (CLK_FREQ / 1_000_000) * MIN_WIDTH_US;
    localparam integer MAX_CYCLES = (CLK_FREQ / 1_000) * MAX_WIDTH_MS;

    reg sync_0, sync_1, signal_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0      <= 1;
            sync_1      <= 1;
            signal_prev <= 1;
        end else begin
            sync_0      <= signal_in;
            sync_1      <= sync_0;
            signal_prev <= sync_1;
        end
    end

    wire signal_falling = (signal_prev == 1'b1) && (sync_1 == 1'b0);
    wire signal_rising  = (signal_prev == 1'b0) && (sync_1 == 1'b1);

    reg [31:0] pulse_counter;
    reg        counting;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_counter <= 0;
            counting      <= 0;
            valid_pulse   <= 0;
        end else begin
            valid_pulse <= 0;  // 1Å¬·° ÆÞ½º Ãâ·Â

            if (signal_falling) begin
                counting <= 1;
                pulse_counter <= 0;
            end else if (counting) begin
                if (sync_1 == 1'b0) begin
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
