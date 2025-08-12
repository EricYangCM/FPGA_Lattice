// -----------------------------------------------------------------------------
// UART_Frame_Consumer
// - UART_Rx_Stack 의 출력(frame_done, field_* 버스, rd_* 포트)을 받아
//   특정 커맨드 파싱(예: "Test", 인자 두 개의 정수) 예시를 구현
// - field[0] == "Test" 이면 cmd_test_valid=1 펄스와 함께 arg1, arg2 정수 출력
// - rd_field/rd_index를 구동해 field[0] 문자열을 안전하게 비교(FSM로 1클럭 지연 접근)
// ----------------------------------------------------------------------------- 
module UART_Frame_Consumer #(
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

    // random read port to access ASCII
    output reg  [$clog2(MAX_FIELDS)-1:0]    rd_field,
    output reg  [$clog2(MAX_FIELD_LEN)-1:0] rd_index,
    input  wire [7:0]  rd_char,
    input  wire        rd_char_valid,

    // parsed outputs (example for command "Test,<arg1>,<arg2>*")
    output reg         cmd_test_valid,   // 1clk pulse when "Test" parsed
    output reg  [31:0] arg1,             // field[1] (if numeric)
    output reg  [31:0] arg2,             // field[2] (if numeric)

    // status
    output reg         unknown_cmd,      // 1clk pulse if field0!=known
    output reg         parse_busy        // 내부 비교 중 busy 표시(옵션)
);

    // ------- helpers: slice functions -------
    function [7:0] FLEN_AT;
        input integer idx;
        begin
            FLEN_AT = field_len_bus[8*idx +: 8];
        end
    endfunction

    function [31:0] INT_AT;
        input integer idx;
        begin
            INT_AT = int_values_bus[32*idx +: 32];
        end
    endfunction

    // ------- FSM --------
    typedef enum logic [2:0] {S_IDLE, S_CMD0_INIT, S_CMD0_RD, S_CMD0_CMP, S_LATCH_ARGS, S_DONE} st_t;
    st_t st;

    // 비교 대상 문자열: "Test"
    localparam [7:0] C_T = "T";
    localparam [7:0] C_e = "e";
    localparam [7:0] C_s = "s";
    localparam [7:0] C_t = "t";

    reg [7:0] cmd0_len;
    reg [1:0] idx_cmp;           // 0..3 for "T","e","s","t"
    reg       cmd0_match;

    // start
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            st             <= S_IDLE;
            rd_field       <= {($clog2(MAX_FIELDS)){1'b0}};
            rd_index       <= {($clog2(MAX_FIELD_LEN)){1'b0}};
            cmd0_len       <= 8'd0;
            idx_cmp        <= 2'd0;
            cmd0_match     <= 1'b0;
            cmd_test_valid <= 1'b0;
            arg1           <= 32'd0;
            arg2           <= 32'd0;
            unknown_cmd    <= 1'b0;
            parse_busy     <= 1'b0;
        end else begin
            // default pulses
            cmd_test_valid <= 1'b0;
            unknown_cmd    <= 1'b0;

            case(st)
                S_IDLE: begin
                    parse_busy <= 1'b0;
                    if(frame_done) begin
                        // 준비: field[0] 비교
                        parse_busy <= 1'b1;
                        cmd0_len   <= FLEN_AT(0);
                        cmd0_match <= 1'b0;
                        idx_cmp    <= 2'd0;
                        rd_field   <= 0;
                        rd_index   <= 0;
                        st         <= S_CMD0_INIT;
                    end
                end

                // 한 클럭 여유 준 후 첫 글자 읽기
                S_CMD0_INIT: begin
                    // 길이가 4가 아니면 "Test"와 불일치
                    if(cmd0_len != 8'd4) begin
                        st <= S_LATCH_ARGS; // 그래도 인자 캐치는 해두고 unknown 처리
                        cmd0_match <= 1'b0;
                    end else begin
                        st <= S_CMD0_RD; // rd_index=0에서 rd_char 읽기 대기
                    end
                end

                // rd_char 유효 사이클
                S_CMD0_RD: begin
                    st <= S_CMD0_CMP; // 다음 사이클에 비교
                end

                S_CMD0_CMP: begin
                    // 기대 문자 선택
                    reg [7:0] exp;
                    case(idx_cmp)
                        2'd0: exp = C_T;
                        2'd1: exp = C_e;
                        2'd2: exp = C_s;
                        default: exp = C_t;
                    endcase

                    if(!rd_char_valid || (rd_char != exp)) begin
                        // 불일치
                        cmd0_match <= 1'b0;
                        st         <= S_LATCH_ARGS;
                    end else begin
                        // 일치 → 다음 글자
                        if(idx_cmp == 2'd3) begin
                            cmd0_match <= 1'b1;  // "Test" 완전 매칭
                            st         <= S_LATCH_ARGS;
                        end else begin
                            idx_cmp  <= idx_cmp + 1'b1;
                            rd_index <= rd_index + 1'b1;
                            st       <= S_CMD0_RD;  // 다음 문자를 읽으러
                        end
                    end
                end

                // 인자 래치(공통): field[1], field[2]가 숫자면 int_values로
                S_LATCH_ARGS: begin
                    // field_count >= 2/3 체크
                    if (field_count > 8'd1 && is_digit_only_mask[1]) arg1 <= INT_AT(1);
                    else                                           arg1 <= 32'd0;

                    if (field_count > 8'd2 && is_digit_only_mask[2]) arg2 <= INT_AT(2);
                    else                                           arg2 <= 32'd0;

                    st <= S_DONE;
                end

                S_DONE: begin
                    parse_busy <= 1'b0;
                    if(cmd0_match) begin
                        cmd_test_valid <= 1'b1;  // "Test,<arg1>,<arg2>*" 커맨드 유효
                    end else begin
                        unknown_cmd <= 1'b1;     // field0이 "Test"가 아닌 경우
                    end
                    st <= S_IDLE;
                end
            endcase
        end
    end

endmodule
