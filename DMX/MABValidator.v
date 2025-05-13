module MABValidator #(
    parameter CLK_FREQ     = 20_000_000,
    parameter MAB_MIN_US   = 12,
    parameter MAB_MAX_US   = 100
)(
    input  wire clk,
    input  wire rst_n,
    input  wire signal_in,

    output reg  mab_valid   // 1 pulse generation when valid MAB detected
);

    localparam integer MAB_MIN_CYCLES = (CLK_FREQ / 1_000_000) * MAB_MIN_US;
    localparam integer MAB_MAX_CYCLES = (CLK_FREQ / 1_000_000) * MAB_MAX_US;

    // Sync
    reg sync_0, sync_1, signal_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0 <= 1;
            sync_1 <= 1;
            signal_prev <= 1;
        end else begin
            sync_0      <= signal_in;
            sync_1      <= sync_0;
            signal_prev <= sync_1;
        end
    end

    wire signal_rising  = (signal_prev == 1'b0) && (sync_1 == 1'b1);
    wire signal_falling = (signal_prev == 1'b1) && (sync_1 == 1'b0);

    reg [31:0] mab_counter;
    reg        counting;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mab_counter <= 0;
            counting    <= 0;
            mab_valid   <= 0;
        end else begin
            mab_valid <= 0;

            if (signal_rising) begin
                counting <= 1;
                mab_counter <= 0;
            end else if (counting) begin
                if (sync_1 == 1'b1) begin
                    // Keep HIGH
                    mab_counter <= mab_counter + 1;
                    if (mab_counter > MAB_MAX_CYCLES) begin
                        counting <= 0;  // timeout
                    end
                end else if (signal_falling) begin
                    if (mab_counter >= MAB_MIN_CYCLES && mab_counter <= MAB_MAX_CYCLES) begin
                        mab_valid <= 1;  // valid MAB
                    end
                    counting <= 0;
                end
            end
        end
    end

endmodule
