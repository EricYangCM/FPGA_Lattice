// ============================================================================
// UART Rx → FIFO_DC → Tokenizer( '$'..'*' , ',' 구분 ) → Field Assembler
// One-file drop-in stack
//   - Top: UART_Rx_Stack
//   - Edit only: module name of FIFO IP inside UART_Rx_FIFO (FIFO_UART_RX)
// ----------------------------------------------------------------------------
// Tool: Verilog-2001 (+ $clog2 사용)
// ============================================================================

// -----------------------------------------------------------------------------
// 1) UART Receiver (8-N-1), 16x oversampling, with 2FF sync
// -----------------------------------------------------------------------------
module UART_RX #
(
    parameter integer CLK_HZ       = 48_000_000,
    parameter integer BAUD         = 115_200,
    parameter integer OVERSAMPLE   = 16,
    parameter integer READY_WIDTH  = 4
)
(
    input  wire clk,
    input  wire rst_n,

    input  wire rx_i,               // idle=1
    output reg  [7:0] data,
    output reg        byte_ready,    // READY_WIDTH clocks
    output reg        byte_done,     // gap timeout pulse (unused by default)
    output reg        frame_err,     // stop-bit low
    output reg        rx_busy
);

    // sample tick: CLK/(BAUD*OVERSAMPLE)
    localparam integer DIV_ROUND = (CLK_HZ + (BAUD*OVERSAMPLE)/2) / (BAUD*OVERSAMPLE);
    localparam integer DIV       = (DIV_ROUND < 1) ? 1 : DIV_ROUND;

    reg [$clog2(DIV)-1:0]  div_cnt = 0;
    wire sample_tick = (div_cnt == 0);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) div_cnt <= 0;
        else       div_cnt <= (div_cnt == 0) ? (DIV-1) : (div_cnt - 1);
    end

    // 2FF input sync
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rx_sync1 <= 1'b1; rx_sync2 <= 1'b1; end
        else begin rx_sync1 <= rx_i; rx_sync2 <= rx_sync1; end
    end
    wire rx = rx_sync2;

    // FSM
    localparam [1:0] S_IDLE=2'd0, S_START=2'd1, S_DATA=2'd2, S_STOP=2'd3;
    reg [1:0] st = S_IDLE;

    reg [$clog2(OVERSAMPLE)-1:0] os_cnt = 0;
    reg [2:0] bit_idx = 0;
    reg [7:0] shreg   = 8'h00;

    // byte_ready stretch
    reg [$clog2(READY_WIDTH+1)-1:0] ready_cnt = 0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            byte_ready <= 1'b0;
            ready_cnt  <= 0;
        end else begin
            if(ready_cnt != 0) begin
                ready_cnt  <= ready_cnt - 1;
                byte_ready <= 1'b1;
            end else begin
                byte_ready <= 1'b0;
            end
        end
    end

    // byte_done (gap) — simple implementation
    localparam integer GAP_TICKS = 20 * OVERSAMPLE;
    reg [$clog2(GAP_TICKS+1)-1:0] gap_cnt = 0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            gap_cnt   <= 0;
            byte_done <= 1'b0;
        end else begin
            byte_done <= 1'b0;
            if(!rx) gap_cnt <= 0;
            else if(sample_tick && (gap_cnt < GAP_TICKS)) gap_cnt <= gap_cnt + 1;
            if(gap_cnt == GAP_TICKS-1 && sample_tick) byte_done <= 1'b1;
        end
    end

    // main
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            st        <= S_IDLE;
            os_cnt    <= 0;
            bit_idx   <= 0;
            shreg     <= 8'h00;
            data      <= 8'h00;
            frame_err <= 1'b0;
            rx_busy   <= 1'b0;
        end else if(sample_tick) begin
            case(st)
                S_IDLE: begin
                    rx_busy   <= 1'b0;
                    frame_err <= 1'b0;
                    if(!rx) begin
                        os_cnt  <= OVERSAMPLE/2;
                        st      <= S_START;
                        rx_busy <= 1'b1;
                    end
                end

                S_START: begin
                    if(os_cnt == 0) begin
                        if(!rx) begin
                            os_cnt  <= OVERSAMPLE-1;
                            bit_idx <= 0;
                            st      <= S_DATA;
                        end else begin
                            st <= S_IDLE;
                        end
                    end else os_cnt <= os_cnt - 1;
                end

                S_DATA: begin
                    if(os_cnt == 0) begin
                        shreg <= {rx, shreg[7:1]}; // LSB first
                        os_cnt <= OVERSAMPLE-1;
                        if(bit_idx == 3'd7) st <= S_STOP;
                        bit_idx <= bit_idx + 1;
                    end else os_cnt <= os_cnt - 1;
                end

                S_STOP: begin
                    if(os_cnt == 0) begin
                        frame_err <= (rx == 1'b0);
                        data      <= shreg;
                        ready_cnt <= READY_WIDTH;
                        st        <= S_IDLE;
                    end else os_cnt <= os_cnt - 1;
                end
            endcase
        end
    end
endmodule


// -----------------------------------------------------------------------------
// 2) UART_Rx_FIFO : UART_RX + FIFO_DC(IPexpress) 래퍼
//    - 주의: 아래 FIFO 인스턴스 모듈명(FIFO_UART_RX)을 환경에 맞게 바꿔주세요!
// -----------------------------------------------------------------------------
module UART_Rx_FIFO #(
    parameter integer CLK_HZ      = 48_000_000,
    parameter integer BAUD        = 115_200,
    parameter integer OVERSAMPLE  = 16,
    parameter integer READY_WIDTH = 4
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,

    input  wire       rd_en,
    output wire [7:0] dout,
    output wire       empty,
    output wire       full,

    output reg  [31:0] overrun_cnt
);
    wire [7:0] rx_data;
    wire       rx_ready, rx_done, rx_ferr;

    UART_RX #(
      .CLK_HZ(CLK_HZ), .BAUD(BAUD),
      .OVERSAMPLE(OVERSAMPLE), .READY_WIDTH(READY_WIDTH)
    ) u_rx (
      .clk(clk), .rst_n(rst_n),
      .rx_i(uart_rx),
      .data(rx_data),
      .byte_ready(rx_ready),
      .byte_done(rx_done),
      .frame_err(rx_ferr),
      .rx_busy()
    );

    wire [7:0] fifo_q;
    wire       fifo_empty, fifo_full;

    wire wr_en = rx_ready & ~fifo_full;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) overrun_cnt <= 32'd0;
        else if (rx_ready && fifo_full) overrun_cnt <= overrun_cnt + 1'b1;
    end

    // ====== IPexpress FIFO Module Instance ======
    // Replace 'FIFO_UART_RX' with your generated module name if different.
    FIFO_UART_RX u_fifo (
      .Data        (rx_data),   // [7:0]
      .Q           (fifo_q),    // [7:0]
      .WrClock     (clk),
      .RdClock     (clk),
      .WrEn        (wr_en),
      .RdEn        (rd_en),
      .Reset       (~rst_n),    // active-high
      .RPReset     (1'b0),
      .Empty       (fifo_empty),
      .Full        (fifo_full),
      .AlmostEmpty (/*unused*/),
      .AlmostFull  (/*unused*/)
    );

    assign dout  = fifo_q;
    assign empty = fifo_empty;
    assign full  = fifo_full;
endmodule


// -----------------------------------------------------------------------------
// 3) UART_Rx_Processor : '$' .. '*' 프레임, ',' 구분자, CR/LF 무시
// -----------------------------------------------------------------------------
module UART_Rx_Processor (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       UART_Empty,
    input  wire [7:0] UART_Dout,
    output reg        UART_RD_EN,

    output reg        frame_start,
    output reg        frame_end,
    output reg        ch_valid,
    output reg [7:0]  ch_data,
    output reg        ch_is_sep
);
    localparam S_WAIT_STX = 2'd0;
    localparam S_POP      = 2'd1;
    localparam S_USE      = 2'd2;
    reg [1:0] st;

    reg in_frame;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            UART_RD_EN  <= 1'b0;
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            ch_valid    <= 1'b0;
            ch_data     <= 8'h00;
            ch_is_sep   <= 1'b0;

            st        <= S_WAIT_STX;
            in_frame  <= 1'b0;
        end else begin
            UART_RD_EN  <= 1'b0;
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            ch_valid    <= 1'b0;
            ch_is_sep   <= 1'b0;

            case (st)
                S_WAIT_STX: begin
                    if(!UART_Empty) begin
                        UART_RD_EN <= 1'b1;
                        st         <= S_POP;
                    end
                end

                S_POP: begin
                    st <= S_USE;
                end

                S_USE: begin
                    // 프레임 밖: '$' 찾기 (0x24)
                    if(!in_frame) begin
                        if (UART_Dout == 8'h24) begin
                            in_frame   <= 1'b1;
                            frame_start<= 1'b1;
                        end
                        if(!UART_Empty) begin
                            UART_RD_EN <= 1'b1;
                            st         <= S_POP;
                        end else begin
                            st         <= S_WAIT_STX;
                        end
                    end
                    // 프레임 안
                    else begin
                        if (UART_Dout == 8'h2A) begin // '*'
                            in_frame  <= 1'b0;
                            frame_end <= 1'b1;
                            if(!UART_Empty) begin
                                UART_RD_EN <= 1'b1;
                                st         <= S_POP;
                            end else begin
                                st         <= S_WAIT_STX;
                            end
                        end
                        else if (UART_Dout == 8'h0D || UART_Dout == 8'h0A) begin
                            if(!UART_Empty) begin
                                UART_RD_EN <= 1'b1;
                                st         <= S_POP;
                            end else begin
                                st         <= S_WAIT_STX;
                            end
                        end
                        else begin
                            ch_data   <= UART_Dout;
                            ch_valid  <= 1'b1;
                            ch_is_sep <= (UART_Dout == 8'h2C); // ','

                            if(!UART_Empty) begin
                                UART_RD_EN <= 1'b1;
                                st         <= S_POP;
                            end else begin
                                st         <= S_WAIT_STX;
                            end
                        end
                    end
                end
            endcase
        end
    end
endmodule


// -----------------------------------------------------------------------------
// 4) UART_FieldAssembler : 필드 버퍼링 + 숫자필드(int32) 파싱
// -----------------------------------------------------------------------------
module UART_FieldAssembler #(
    parameter integer MAX_FIELDS     = 8,
    parameter integer MAX_FIELD_LEN  = 16
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        frame_start,
    input  wire        frame_end,
    input  wire        ch_valid,
    input  wire [7:0]  ch_data,
    input  wire        ch_is_sep,

    output reg         frame_done,
    output reg  [7:0]  field_count,

    input  wire [$clog2(MAX_FIELDS)-1:0]     rd_field,
    input  wire [$clog2(MAX_FIELD_LEN)-1:0]  rd_index,
    output wire [7:0]  rd_char,
    output wire        rd_char_valid,

    output reg  [MAX_FIELDS*8-1:0]   field_len_bus,
    output reg  [MAX_FIELDS-1:0]     is_digit_only_mask,
    output reg  [MAX_FIELDS*32-1:0]  int_values_bus,
    output reg  [31:0]               overrun_count
);
    localparam integer MEM_SIZE = MAX_FIELDS * MAX_FIELD_LEN;
    (* ram_style="distributed" *) reg [7:0] mem [0:MEM_SIZE-1];

    reg [7:0]  field_len   [0:MAX_FIELDS-1];
    reg        is_digit_only [0:MAX_FIELDS-1];
    reg [31:0] int_value     [0:MAX_FIELDS-1];
    reg        int_neg       [0:MAX_FIELDS-1];

    reg [$clog2(MAX_FIELDS)-1:0]    cur_field;
    reg [$clog2(MAX_FIELD_LEN)-1:0] cur_index;

    wire [$clog2(MEM_SIZE)-1:0] wr_addr = cur_field*MAX_FIELD_LEN + cur_index;
    wire [$clog2(MEM_SIZE)-1:0] rd_addr = rd_field *MAX_FIELD_LEN + rd_index;

    assign rd_char       = mem[rd_addr];
    assign rd_char_valid = (rd_index < field_len[rd_field]);

    integer i;

    task pack_outputs;
        integer k;
        begin
            for(k=0;k<MAX_FIELDS;k=k+1) begin
                field_len_bus[8*k +: 8]     = field_len[k];
                is_digit_only_mask[k]       = is_digit_only[k];
                int_values_bus[32*k +: 32]  = int_neg[k] ? (~int_value[k] + 1) : int_value[k];
            end
        end
    endtask

    // ASCII helpers
    wire is_digit = (ch_data >= 8'h30 && ch_data <= 8'h39);      // '0'..'9'
    wire is_sign  = (ch_data == 8'h2B || ch_data == 8'h2D);      // '+' or '-'

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            frame_done    <= 1'b0;
            field_count   <= 8'd0;
            cur_field     <= {($clog2(MAX_FIELDS)){1'b0}};
            cur_index     <= {($clog2(MAX_FIELD_LEN)){1'b0}};
            overrun_count <= 32'd0;

            for(i=0;i<MAX_FIELDS;i=i+1) begin
                field_len[i]     <= 8'd0;
                is_digit_only[i] <= 1'b1;
                int_value[i]     <= 32'd0;
                int_neg[i]       <= 1'b0;
            end
            pack_outputs();
        end
        else begin
            frame_done <= 1'b0;

            if(frame_start) begin
                cur_field   <= 0;
                cur_index   <= 0;
                field_count <= 0;
                for(i=0;i<MAX_FIELDS;i=i+1) begin
                    field_len[i]     <= 0;
                    is_digit_only[i] <= 1'b1;
                    int_value[i]     <= 0;
                    int_neg[i]       <= 1'b0;
                end
                pack_outputs();
            end

            if(ch_valid) begin
                if(ch_is_sep) begin
                    if(cur_field < MAX_FIELDS-1) begin
                        cur_field   <= cur_field + 1'b1;
                        cur_index   <= {($clog2(MAX_FIELD_LEN)){1'b0}};
                        field_count <= (field_count < MAX_FIELDS) ? (field_count + 1'b1) : field_count;
                    end
                end else begin
                    if(cur_field < MAX_FIELDS) begin
                        if(cur_index < MAX_FIELD_LEN) begin
                            mem[wr_addr] <= ch_data;
                            cur_index    <= cur_index + 1'b1;
                            field_len[cur_field] <= field_len[cur_field] + 1'b1;

                            if(is_digit_only[cur_field]) begin
                                if(field_len[cur_field] == 0) begin
                                    if(is_sign) begin
                                        int_neg[cur_field] <= (ch_data == 8'h2D);
                                    end else if(is_digit) begin
                                        int_value[cur_field] <= (ch_data - 8'h30);
                                    end else begin
                                        is_digit_only[cur_field] <= 1'b0;
                                    end
                                end else begin
                                    if(is_digit) begin
                                        int_value[cur_field] <= (int_value[cur_field] * 10) + (ch_data - 8'h30);
                                    end else begin
                                        is_digit_only[cur_field] <= 1'b0;
                                    end
                                end
                            end
                        end else begin
                            overrun_count <= overrun_count + 1'b1;
                        end
                    end
                end
            end

            if(frame_end) begin
                if(cur_field < MAX_FIELDS)
                    field_count <= (cur_field + 1);

                frame_done <= 1'b1;
                pack_outputs();
            end
        end
    end
endmodule


// -----------------------------------------------------------------------------
// 5) UART_Rx_Stack : 최상위 묶음 (이 모듈만 인스턴스해서 쓰면 됨)
//    - UART 핀만 넣으면 frame_done과 필드 결과가 나옵니다.
// -----------------------------------------------------------------------------
module UART_Rx_Stack #(
    parameter integer CLK_HZ      = 48_000_000,
    parameter integer BAUD        = 115_200,
    parameter integer MAX_FIELDS  = 8,
    parameter integer MAX_FIELD_LEN = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,

    // 결과 신호
    output wire        frame_done,
    output wire [7:0]  field_count,
    output wire [MAX_FIELDS*8-1:0]   field_len_bus,
    output wire [MAX_FIELDS-1:0]     is_digit_only_mask,
    output wire [MAX_FIELDS*32-1:0]  int_values_bus,

    // 임의 접근(ASCII)
    input  wire [$clog2(MAX_FIELDS)-1:0]    rd_field,
    input  wire [$clog2(MAX_FIELD_LEN)-1:0] rd_index,
    output wire [7:0] rd_char,
    output wire       rd_char_valid,

    // 모니터링
    output wire [31:0] uart_overrun_cnt
);
    // UART Rx + FIFO
    wire [7:0] fifo_dout;
    wire       fifo_empty, fifo_full;
    wire       rd_en_pulse;

    UART_Rx_FIFO #(
      .CLK_HZ(CLK_HZ), .BAUD(BAUD)
    ) u_rxfifo (
      .clk(clk), .rst_n(rst_n),
      .uart_rx(uart_rx),
      .rd_en(rd_en_pulse),
      .dout(fifo_dout),
      .empty(fifo_empty),
      .full(fifo_full),
      .overrun_cnt(uart_overrun_cnt)
    );

    // Tokenizer
    wire frame_start, frame_end_w;
    wire ch_valid;
    wire [7:0] ch_data;
    wire ch_is_sep;

    UART_Rx_Processor u_tok (
      .clk(clk), .rst_n(rst_n),
      .UART_Empty(fifo_empty),
      .UART_Dout (fifo_dout),
      .UART_RD_EN(rd_en_pulse),
      .frame_start(frame_start),
      .frame_end  (frame_end_w),
      .ch_valid   (ch_valid),
      .ch_data    (ch_data),
      .ch_is_sep  (ch_is_sep)
    );

    // Field Assembler
    UART_FieldAssembler #(
      .MAX_FIELDS(MAX_FIELDS),
      .MAX_FIELD_LEN(MAX_FIELD_LEN)
    ) u_fasm (
      .clk(clk), .rst_n(rst_n),
      .frame_start(frame_start),
      .frame_end  (frame_end_w),
      .ch_valid(ch_valid),
      .ch_data(ch_data),
      .ch_is_sep(ch_is_sep),

      .frame_done(frame_done),
      .field_count(field_count),

      .rd_field(rd_field), .rd_index(rd_index),
      .rd_char(rd_char), .rd_char_valid(rd_char_valid),

      .field_len_bus(field_len_bus),
      .is_digit_only_mask(is_digit_only_mask),
      .int_values_bus(int_values_bus),
      .overrun_count(/*unused*/)
    );

endmodule
