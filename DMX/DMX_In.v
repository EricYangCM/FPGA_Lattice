module DMX_Input_Module #(
    parameter CLK_FREQ = 20_000_000,
    parameter BAUD_RATE = 250_000,
    parameter DMX_BUFFER_SIZE = 513
)(
    input  wire clk,
    input  wire rst_n,
    input  wire DMX_Input_Signal,

    input  wire [9:0] EBR_Addr_B,
    input  wire [7:0] EBR_QB,

    output reg  DE,
    output reg  Signal_Receiving_LED,
    output reg  [9:0] Last_Received_ByteCount
);

    // ------------------- Break Detection -------------------
    wire IsBreak;
    BreakValidator BreakValidator_inst (
        .clk(clk),
        .rst_n(rst_n),
        .signal_in(DMX_Input_Signal),
        .valid_pulse(IsBreak)
    );

    // ------------------- Byte Receive -------------------
    wire byte_ready;
    wire [7:0] received_byte;

    ByteReceiver #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) ByteReceiver_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_receive(1'b1),  // 항상 수신 상태
        .DMX_Input_Signal(DMX_Input_Signal),
        .byte_ready(byte_ready),
        .received_byte(received_byte)
    );
	

    // ------------------- EBR -------------------
    reg  [9:0] EBR_Addr_A;
    reg  [7:0] EBR_Data_In_A;
    reg        EBR_WrA;

    EBR EBR_Inst (
        .ClockA(clk), .ClockB(clk),
        .ResetA(~rst_n), .ResetB(~rst_n),
        .ClockEnA(1'b1), .ClockEnB(1'b1),
        .WrA(EBR_WrA),
        .AddressA(EBR_Addr_A),
        .DataInA(EBR_Data_In_A),
        .WrB(1'b0),
        .AddressB(EBR_Addr_B),
        .QB(EBR_QB)
    );

    // -------------------전체 수신 Timeout (Break 기준) -------------------
    reg timeout_enable;
    wire dmx_timeout;

    Timeout_Timer_ms #(
        .CLK_FREQ(CLK_FREQ), .TIMEOUT_MS(300)
    ) Timeout_Timer_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(timeout_enable),
        .timeout(dmx_timeout)
    );


    // ------------------- Logic -------------------
    reg [9:0] byte_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            DE <= 1'b0;
            byte_counter <= 0;
            Signal_Receiving_LED <= 0;
            EBR_Addr_A <= 0;
            EBR_Data_In_A <= 0;
            EBR_WrA <= 0;
            timeout_enable <= 0;
            Last_Received_ByteCount <= 0;
        end else begin
            timeout_enable <= ~IsBreak;
            Signal_Receiving_LED <= ~dmx_timeout;
			
            EBR_WrA <= 1'b0;
            
			// Break 감지 시 주소 리셋 + 마지막 수신 길이 저장
			if (IsBreak) begin
                Last_Received_ByteCount <= byte_counter;
                byte_counter <= 0;
            end
            // byte_ready
            else if (byte_ready) begin
                if (byte_counter < DMX_BUFFER_SIZE) begin
                    EBR_Addr_A    <= byte_counter;
                    EBR_Data_In_A <= received_byte;
                    EBR_WrA       <= 1'b1;
                    byte_counter  <= byte_counter + 1;
                end
				
            end
			

        end
    end

endmodule
