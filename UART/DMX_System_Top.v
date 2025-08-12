module DMX_System_Top #(
    parameter integer CLK_HZ = 48_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,         // MCU → FPGA ASCII: $DIM,<port>,<ch>,<level>*

    output wire DMX_TX_1,
    output wire DMX_TX_2,
    output wire DMX_TX_3,
    output wire DMX_TX_4,
    output wire DE_1,            // 필요없으면 안 뽑아도 됨
    output wire DE_2,
    output wire DE_3,
    output wire DE_4
);

    // -----------------------------
    // 1) UART 수신 + 필드 파서 스택
    // -----------------------------
    wire        frame_done;
    wire [7:0]  field_count;
    wire [8*8-1:0]  field_len_bus;        // MAX_FIELDS=8
    wire [7:0]      is_digit_only_mask;
    wire [32*8-1:0] int_values_bus;

    wire [$clog2(8)-1:0]   rd_field;
    wire [$clog2(16)-1:0]  rd_index;
    wire [7:0]             rd_char;
    wire                   rd_char_valid;

    wire [31:0] uart_overrun_cnt;

    UART_Rx_Stack #(
      .CLK_HZ(CLK_HZ),
      .BAUD(115_200),
      .MAX_FIELDS(8),
      .MAX_FIELD_LEN(16)
    ) u_uart_stack (
      .clk(clk),
      .rst_n(rst_n),
      .uart_rx(uart_rx),

      .frame_done(frame_done),
      .field_count(field_count),
      .field_len_bus(field_len_bus),
      .is_digit_only_mask(is_digit_only_mask),
      .int_values_bus(int_values_bus),

      .rd_field(rd_field),
      .rd_index(rd_index),
      .rd_char(rd_char),
      .rd_char_valid(rd_char_valid),

      .uart_overrun_cnt(uart_overrun_cnt)
    );

    // -----------------------------
    // 2) DIM 전용 소비자
    // -----------------------------
    wire        cmd_dim_valid;
    wire [1:0]  dim_port;      // 0..3
    wire [9:0]  dim_channel;   // 1..512
    wire [7:0]  dim_level;     // 0..255
    wire        err_fieldcount, err_nonnumeric, err_range, unknown_cmd, parse_busy;

    UART_DIM_Consumer #(
      .MAX_FIELDS(8),
      .MAX_FIELD_LEN(16)
    ) u_dim_consumer (
      .clk(clk),
      .rst_n(rst_n),

      .frame_done(frame_done),
      .field_count(field_count),
      .field_len_bus(field_len_bus),
      .is_digit_only_mask(is_digit_only_mask),
      .int_values_bus(int_values_bus),

      .rd_field(rd_field),
      .rd_index(rd_index),
      .rd_char(rd_char),
      .rd_char_valid(rd_char_valid),

      .cmd_dim_valid(cmd_dim_valid),
      .dim_port(dim_port),
      .dim_channel(dim_channel),
      .dim_level(dim_level),

      .err_fieldcount(err_fieldcount),
      .err_nonnumeric(err_nonnumeric),
      .err_range(err_range),
      .unknown_cmd(unknown_cmd),
      .parse_busy(parse_busy)
    );

    // -----------------------------
    // 3) 4개 DMX 모듈 인스턴스
    //    - 각 모듈의 EBR Port-B에 쓰기 신호 연결
    // -----------------------------
    // Port 0
    reg        wr0_pulse;
    reg [9:0]  wr0_addr;
    reg [7:0]  wr0_data;

    // Port 1
    reg        wr1_pulse;
    reg [9:0]  wr1_addr;
    reg [7:0]  wr1_data;

    // Port 2
    reg        wr2_pulse;
    reg [9:0]  wr2_addr;
    reg [7:0]  wr2_data;

    // Port 3
    reg        wr3_pulse;
    reg [9:0]  wr3_addr;
    reg [7:0]  wr3_data;

    // DIM 명령 수신 시, 해당 포트의 EBR-B에 1클럭 쓰기
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr0_pulse <= 1'b0; wr1_pulse <= 1'b0; wr2_pulse <= 1'b0; wr3_pulse <= 1'b0;
            wr0_addr  <= 10'd0; wr1_addr <= 10'd0; wr2_addr <= 10'd0; wr3_addr <= 10'd0;
            wr0_data  <= 8'd0;  wr1_data <= 8'd0;  wr2_data <= 8'd0;  wr3_data <= 8'd0;
        end else begin
            // 기본 0
            wr0_pulse <= 1'b0; wr1_pulse <= 1'b0; wr2_pulse <= 1'b0; wr3_pulse <= 1'b0;

            if (cmd_dim_valid) begin
                // 주소 매핑: 채널 1..512 → EBR 주소 0..511
                // (Start Code를 따로 쓰려면 주소 +1 하고 Channel_Count=513로 운영)
                case (dim_port)
                  2'd0: begin wr0_addr <= dim_channel - 10'd1; wr0_data <= dim_level; wr0_pulse <= 1'b1; end
                  2'd1: begin wr1_addr <= dim_channel - 10'd1; wr1_data <= dim_level; wr1_pulse <= 1'b1; end
                  2'd2: begin wr2_addr <= dim_channel - 10'd1; wr2_data <= dim_level; wr2_pulse <= 1'b1; end
                  2'd3: begin wr3_addr <= dim_channel - 10'd1; wr3_data <= dim_level; wr3_pulse <= 1'b1; end
                endcase
            end
        end
    end

    // DMX 4포트(주파수 모드는 예시로 모두 30Hz=2'b10, Enable=1)
    DMX_Output_Module #(
      .CLK_FREQ(CLK_HZ),
      .BAUD_RATE(250_000),
      .WAIT_CYCLES(10)
    ) DMX_Out_1 (
      .clk(clk), .rst_n(rst_n),
      .EBR_Addr_B (wr0_addr),
      .EBR_DataIn_B(wr0_data),
      .EBR_WrB    (wr0_pulse),
      .Channel_Count(10'd512),
      .Enable(1'b1),
      .FREQ_MODE(2'b10),
      .DE(DE_1),
      .DMX_Output_Signal(DMX_TX_1)
    );

    DMX_Output_Module #(
      .CLK_FREQ(CLK_HZ),
      .BAUD_RATE(250_000),
      .WAIT_CYCLES(10)
    ) DMX_Out_2 (
      .clk(clk), .rst_n(rst_n),
      .EBR_Addr_B (wr1_addr),
      .EBR_DataIn_B(wr1_data),
      .EBR_WrB    (wr1_pulse),
      .Channel_Count(10'd512),
      .Enable(1'b1),
      .FREQ_MODE(2'b10),
      .DE(DE_2),
      .DMX_Output_Signal(DMX_TX_2)
    );

    DMX_Output_Module #(
      .CLK_FREQ(CLK_HZ),
      .BAUD_RATE(250_000),
      .WAIT_CYCLES(10)
    ) DMX_Out_3 (
      .clk(clk), .rst_n(rst_n),
      .EBR_Addr_B (wr2_addr),
      .EBR_DataIn_B(wr2_data),
      .EBR_WrB    (wr2_pulse),
      .Channel_Count(10'd512),
      .Enable(1'b1),
      .FREQ_MODE(2'b10),
      .DE(DE_3),
      .DMX_Output_Signal(DMX_TX_3)
    );

    DMX_Output_Module #(
      .CLK_FREQ(CLK_HZ),
      .BAUD_RATE(250_000),
      .WAIT_CYCLES(10)
    ) DMX_Out_4 (
      .clk(clk), .rst_n(rst_n),
      .EBR_Addr_B (wr3_addr),
      .EBR_DataIn_B(wr3_data),
      .EBR_WrB    (wr3_pulse),
      .Channel_Count(10'd512),
      .Enable(1'b1),
      .FREQ_MODE(2'b10),
      .DE(DE_4),
      .DMX_Output_Signal(DMX_TX_4)
    );

endmodule
