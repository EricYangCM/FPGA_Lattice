module DMX_Input_Module #(
    parameter CLK_FREQ = 20_000_000,
    parameter BAUD_RATE = 250_000,
    parameter DMX_BUFFER_SIZE = 513
)(
    input  wire clk,
    input  wire rst_n,
    input  wire DMX_Input_Signal,

    output reg  DE,
    output reg  [(8*DMX_BUFFER_SIZE-1):0] DMX_Data,
    output reg  [9:0] N_Of_Data,
    output reg  Signal_Receiving_LED,
    output reg  [9:0] TP
);

    // ------------------------------
    // Break / MAB 감지기
    wire IsBreak;
    wire IsMAB;

    BreakValidator BreakValidator_inst (
        .clk(clk),
        .rst_n(rst_n),
        .signal_in(DMX_Input_Signal),
        .valid_pulse(IsBreak)
    );

    MABValidator MABValidator_inst (
        .clk(clk),
        .rst_n(rst_n),
        .signal_in(DMX_Input_Signal),
        .mab_valid(IsMAB)
    );

    // ------------------------------
    // ByteReceiver 연결
    reg start_byte_receive;
    wire byte_ready;
    wire [7:0] received_byte;
    wire byte_error;
    wire byte_done;

    ByteReceiver #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) ByteReceiver_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_receive(start_byte_receive),
        .DMX_Input_Signal(DMX_Input_Signal),
        .byte_ready(byte_ready),
        .received_byte(received_byte),
        .error(byte_error),
        .byte_done(byte_done)
    );

    // ------------------------------
    // MAB 타임아웃 타이머 (예: 88us)
    wire mab_timeout;
    reg mab_timeout_enable;

    Timeout_Timer_us #(
        .CLK_FREQ(CLK_FREQ),
        .TIMEOUT_US(88)
    ) MAB_Timeout_Timer (
        .clk(clk),
        .rst_n(rst_n),
        .enable(mab_timeout_enable),
        .timeout(mab_timeout)
    );

    // ------------------------------
    // EBR RAM
    reg         EBR_Wr_A;
    reg  [8:0]  EBR_Addr_A;
    reg  [7:0]  EBR_Data_In_A;
    wire [8:0]  EBR_Addr_B = 0;
    wire [63:0] EBR_QB;

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
        .WrB(1'b0),
        .AddressB(EBR_Addr_B),
        .QB(EBR_QB)
    );

    // ------------------------------
    // 통신 상태 모니터링 타이머 (300ms)
    reg timeout_enable;
    wire dmx_timeout;

    Timeout_Timer_ms #(
        .CLK_FREQ(CLK_FREQ),
        .TIMEOUT_MS(300)
    ) Timeout_Timer_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(timeout_enable),
        .timeout(dmx_timeout)
    );

    // ------------------------------
    // FSM 상태 정의
    localparam IDLE         = 0,
               BREAK        = 1,
               MAB          = 2,
               BYTE_RECEIVE = 3;

    reg [3:0] state;
    reg [9:0] byte_counter;

    // ------------------------------
    // FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            DE                   <= 1'b0;
            state                <= IDLE;
            byte_counter         <= 0;
            N_Of_Data            <= 0;
            Signal_Receiving_LED <= 0;
            start_byte_receive   <= 0;
            EBR_Wr_A             <= 0;
            EBR_Addr_A           <= 0;
            EBR_Data_In_A        <= 0;
            timeout_enable       <= 0;
            TP                   <= 0;
            mab_timeout_enable   <= 0;
        end else begin
            // Break 감지되면 타이머 리셋
            timeout_enable <= ~IsBreak;
            Signal_Receiving_LED <= ~dmx_timeout;
            EBR_Wr_A <= 0;

            case (state)
                IDLE: begin
                    byte_counter <= 0;
                    N_Of_Data <= 0;
                    mab_timeout_enable <= 0;
                    state <= BREAK;
                end

                BREAK: begin
                    if (IsBreak) begin
                        state <= MAB;
                        mab_timeout_enable <= 1;
                    end
                end

                MAB: begin
                    if (IsMAB) begin
                        mab_timeout_enable <= 0;
                        start_byte_receive <= 1;
                        state <= BYTE_RECEIVE;
                    end else if (mab_timeout) begin
                        mab_timeout_enable <= 0;
                        state <= BREAK;  // 다시 Break 감지로
                    end
                end

                BYTE_RECEIVE: begin
                    start_byte_receive <= 0;

                    if (byte_ready) begin
                        EBR_Addr_A    <= byte_counter;
                        EBR_Data_In_A <= received_byte;
                        EBR_Wr_A      <= 1;

                        DMX_Data[(byte_counter * 8) +: 8] <= received_byte;
                        byte_counter <= byte_counter + 1;

                        if (byte_counter == 1) begin
                            TP[9:2] <= received_byte;
                            TP[0] <= ~TP[0];
                        end
                    end

                    if (byte_done || byte_error || byte_counter == DMX_BUFFER_SIZE - 1) begin
                        state <= IDLE;
                        N_Of_Data <= byte_counter;
                    end
                end
            endcase
        end
    end

endmodule
