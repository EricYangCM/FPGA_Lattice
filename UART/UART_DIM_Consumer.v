// -----------------------------------------------------------------------------
// UART_DIM_Consumer.v  (Verilog-2001)
// 프로토콜: $DIM,<port:0..3>,<channel:1..512>,<level:0..255>*
//
// - frame_done 시점에 field0 == "DIM" 비교
// - field1..3 숫자 여부 체크(is_digit_only_mask)
// - 범위 검증 후 유효하면 cmd_dim_valid 1클럭과 함께 포트/채널/레벨 출력
// - 오류 시 각 에러 플래그 펄스 출력
// -----------------------------------------------------------------------------
module UART_DIM_Consumer #(
    parameter integer MAX_FIELDS     = 8,
    parameter integer MAX_FIELD_LEN  = 16
)(
    input  wire clk,
    input  wire rst_n,

    // from UART_Rx_Stack
    input  wire        frame_done,
    input  wire [7:0]  field_count,
    input  wire [MAX_FIELDS*8-1:0]   field_len_bus,
    input  wire [MAX_FIELDS-1:0]     is_digit_only_mask,
    input  wire [MAX_FIELDS*32-1:0]  int_values_bus,

    // random read port to access ASCII from the stack (for "DIM" 비교)
    output reg  [W_F-1:0]    rd_field,
    output reg  [W_L-1:0]    rd_index,
    input  wire [7:0]        rd_char,
    input  wire              rd_char_valid,

    // Parsed result (valid when cmd_dim_valid=1 for one clock)
    output reg               cmd_dim_valid,   // 1clk
    output reg  [1:0]        dim_port,        // 0..3
    output reg  [9:0]        dim_channel,     // 1..512  (512 표현 위해 10비트)
    output reg  [7:0]        dim_level,       // 0..255

    // Errors (1clk pulses)
    output reg               err_fieldcount,  // 필드 개수 부족/과다
    output reg               err_nonnumeric,  // 숫자 아님
    output reg               err_range,       // 범위 벗어남
    output reg               unknown_cmd,     // field0 != "DIM"
    output reg               parse_busy
);
    // -------------------------------------------------------------------------
    // clog2 + 포트 폭 상수
    // -------------------------------------------------------------------------
    function integer clog2;
        input integer value;
        integer i;
        begin
            i = 0;
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clog2 = i;
        end
    endfunction

    localparam integer W_F = clog2(MAX_FIELDS);
    localparam integer W_L = clog2(MAX_FIELD_LEN);

    // -------------------------------------------------------------------------
    // 고정 슬라이스 헬퍼 (툴 호환을 위해 변수 인덱스 part-select 지양)
    // -------------------------------------------------------------------------
    // field 길이
    wire [7:0] len0 = field_len_bus[7:0];

    // 숫자 마스크
    wire isnum1 = is_digit_only_mask[1];
    wire isnum2 = is_digit_only_mask[2];
    wire isnum3 = is_digit_only_mask[3];

    // 정수 값 (32비트)
    wire [31:0] int1 = int_values_bus[63:32];
    wire [31:0] int2 = int_values_bus[95:64];
    wire [31:0] int3 = int_values_bus[127:96];

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    reg [2:0] st;
    localparam S_IDLE       = 3'd0;
    localparam S_CMD0_INIT  = 3'd1;
    localparam S_CMD0_RD    = 3'd2;
    localparam S_CMD0_CMP   = 3'd3;
    localparam S_LATCH_VALS = 3'd4;
    localparam S_VALIDATE   = 3'd5;
    localparam S_DONE       = 3'd6;

    // 비교 대상 "DIM"
    localparam [7:0] C_D = 8'h44; // 'D'
    localparam [7:0] C_I = 8'h49; // 'I'
    localparam [7:0] C_M = 8'h4D; // 'M'

    reg [1:0] idx_cmp;     // 0..2
    reg [7:0] exp;
    reg       cmd0_match;

    // 임시 래치(검증 전)
    reg [31:0] tmp_port, tmp_ch, tmp_lvl;

    // -------------------------------------------------------------------------
    // 시퀀서
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            st             <= S_IDLE;
            rd_field       <= {W_F{1'b0}};
            rd_index       <= {W_L{1'b0}};
            idx_cmp        <= 2'd0;
            exp            <= 8'h00;
            cmd0_match     <= 1'b0;

            cmd_dim_valid  <= 1'b0;
            err_fieldcount <= 1'b0;
            err_nonnumeric <= 1'b0;
            err_range      <= 1'b0;
            unknown_cmd    <= 1'b0;
            parse_busy     <= 1'b0;

            dim_port       <= 2'd0;
            dim_channel    <= 10'd0;
            dim_level      <= 8'd0;

            tmp_port       <= 32'd0;
            tmp_ch         <= 32'd0;
            tmp_lvl        <= 32'd0;
        end else begin
            // one-shot pulses
            cmd_dim_valid  <= 1'b0;
            err_fieldcount <= 1'b0;
            err_nonnumeric <= 1'b0;
            err_range      <= 1'b0;
            unknown_cmd    <= 1'b0;

            case (st)
                S_IDLE: begin
                    parse_busy <= 1'b0;
                    if (frame_done) begin
                        parse_busy <= 1'b1;
                        // field0 비교 준비
                        rd_field   <= {W_F{1'b0}}; // 0
                        rd_index   <= {W_L{1'b0}}; // 0
                        idx_cmp    <= 2'd0;
                        cmd0_match <= 1'b0;
                        st         <= S_CMD0_INIT;
                    end
                end

                // 길이 확인 후 첫 문자 읽기 대기
                S_CMD0_INIT: begin
                    // "DIM" 길이는 3, 필드 개수는 최소 4개 필요(DIM + 3 args)
                    if (len0 != 8'd3) begin
                        st <= S_LATCH_VALS; // 어차피 unknown_cmd 처리
                        cmd0_match <= 1'b0;
                    end else begin
                        st <= S_CMD0_RD; // rd_index=0에서 1클럭 기다려 rd_char 안정
                    end
                end

                S_CMD0_RD: begin
                    st <= S_CMD0_CMP;
                end

                S_CMD0_CMP: begin
                    case(idx_cmp)
                        2'd0: exp <= C_D;
                        2'd1: exp <= C_I;
                        default: exp <= C_M;
                    endcase

                    if (!rd_char_valid || (rd_char != exp)) begin
                        cmd0_match <= 1'b0;
                        st         <= S_LATCH_VALS;
                    end else begin
                        if (idx_cmp == 2'd2) begin
                            cmd0_match <= 1'b1;  // "DIM" 매칭
                            st         <= S_LATCH_VALS;
                        end else begin
                            idx_cmp  <= idx_cmp + 2'd1;
                            rd_index <= rd_index + 1'b1;
                            st       <= S_CMD0_RD;
                        end
                    end
                end

                // 공통: 값 래치 (숫자 여부/필드 개수 체크는 다음 단계)
                S_LATCH_VALS: begin
                    // 필드 개수 체크 (DIM + 3 args = 4개 이상)
                    if (field_count < 8'd4) begin
                        err_fieldcount <= 1'b1;
                        st <= S_DONE;
                    end else begin
                        tmp_port <= int1;
                        tmp_ch   <= int2;
                        tmp_lvl  <= int3;
                        st <= S_VALIDATE;
                    end
                end

                // 숫자 여부 및 범위 검증
                S_VALIDATE: begin
                    if (!cmd0_match) begin
                        unknown_cmd <= 1'b1;
                        st <= S_DONE;
                    end
                    else if (!(isnum1 && isnum2 && isnum3)) begin
                        err_nonnumeric <= 1'b1;
                        st <= S_DONE;
                    end
                    else if (!( (tmp_port >= 0) && (tmp_port <= 3) &&
                                (tmp_ch   >= 1) && (tmp_ch   <= 512) &&
                                (tmp_lvl  >= 0) && (tmp_lvl  <= 255) )) begin
                        err_range <= 1'b1;
                        st <= S_DONE;
                    end
                    else begin
                        // 정상: 출력 래치
                        dim_port    <= tmp_port[1:0];
                        dim_channel <= tmp_ch[9:0];  // 1..512 (10비트 필요)
                        dim_level   <= tmp_lvl[7:0];
                        cmd_dim_valid <= 1'b1;
                        st <= S_DONE;
                    end
                end

                S_DONE: begin
                    parse_busy <= 1'b0;
                    st <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
