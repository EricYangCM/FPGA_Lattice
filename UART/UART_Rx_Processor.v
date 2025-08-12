// -----------------------------------------------------------------------------
// UART_Rx_Processor
// - 입력: FIFO 인터페이스(UART_Empty, UART_Dout[7:0])
// - 출력: FIFO 팝 펄스(UART_RD_EN), 프레임/토큰 신호
// - 프로토콜: STX='$', ETX='*', 내부 데이터는 ASCII. 구분자는 ','.
// - CR/LF(0x0D, 0x0A)는 자동 무시.
// - 동작 요약:
//     WAIT_STX: '$' 올 때까지 버림
//     IN_FRAME: '*' 나올 때까지 바이트 스트리밍(ch_valid)
//       - ',' 면 ch_is_sep=1
//       - 그 외는 ch_is_sep=0
//     프레임 경계: frame_start, frame_end 펄스 제공
// - 주의: FIFO 읽기 타이밍 = rd_en 올린 "다음 클럭"에 UART_Dout 유효(일반 Lattice FIFO 설정 기준)
// -----------------------------------------------------------------------------
module UART_Rx_Processor (
    input  wire       clk,
    input  wire       rst_n,

    // FIFO read-side
    input  wire       UART_Empty,       // 1: 비어있음
    input  wire [7:0] UART_Dout,        // FIFO 데이터 (rd_en 다음 클럭에 유효)
    output reg        UART_RD_EN,       // 1클럭 팝 펄스

    // 프레임/토큰 스트림 인터페이스
    output reg        frame_start,      // '$' 감지한 클럭에 1클럭 펄스
    output reg        frame_end,        // '*' 감지한 클럭에 1클럭 펄스
    output reg        ch_valid,         // 프레임 내부 유효 문자
    output reg [7:0]  ch_data,          // 해당 문자
    output reg        ch_is_sep         // 1이면 ','(필드 구분자)
);

    // 상태
    localparam S_WAIT_STX = 2'd0;
    localparam S_POP      = 2'd1;  // rd_en 1클럭
    localparam S_USE      = 2'd2;  // 다음 클럭에 UART_Dout 유효
    reg [1:0] st;

    // 프레임 안/밖
    reg in_frame;

    // 방금 읽은 바이트 홀드
    reg [7:0] byte_r;

    // 기본 출력 클리어
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
            byte_r    <= 8'h00;
        end else begin
            // 1클럭 펄스류 기본 내림
            UART_RD_EN  <= 1'b0;
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            ch_valid    <= 1'b0;
            ch_is_sep   <= 1'b0;

            case (st)
                // '$' 올 때까지 계속 팝하면서 확인
                S_WAIT_STX: begin
                    if(!UART_Empty) begin
                        UART_RD_EN <= 1'b1;     // 팝 요청
                        st         <= S_POP;
                    end
                    // 팝 결과는 다음 클럭 S_USE에서 확인
                end

                S_POP: begin
                    // 다음 클럭에 UART_Dout 유효
                    st <= S_USE;
                end

                S_USE: begin
                    byte_r <= UART_Dout;

                    // 프레임 밖일 때: STX('$')만 찾음
                    if(!in_frame) begin
                        if (UART_Dout == 8'h24) begin // '$'
                            in_frame   <= 1'b1;
                            frame_start<= 1'b1;
                        end
                        // 다음 바이트 읽기
                        if(!UART_Empty) begin
                            UART_RD_EN <= 1'b1;
                            st         <= S_POP;
                        end else begin
                            st         <= S_WAIT_STX;
                        end
                    end
                    // 프레임 안일 때: ETX('*') 또는 데이터/구분자 처리
                    else begin
                        if (UART_Dout == 8'h2A) begin // '*'
                            in_frame  <= 1'b0;
                            frame_end <= 1'b1;
                            // 프레임 종료 후 다음 바이트 준비
                            if(!UART_Empty) begin
                                UART_RD_EN <= 1'b1;
                                st         <= S_POP;
                            end else begin
                                st         <= S_WAIT_STX;
                            end
                        end
                        else if (UART_Dout == 8'h0D || UART_Dout == 8'h0A) begin
                            // CR/LF 무시, 계속 진행
                            if(!UART_Empty) begin
                                UART_RD_EN <= 1'b1;
                                st         <= S_POP;
                            end else begin
                                st         <= S_WAIT_STX;
                            end
                        end
                        else begin
                            // 데이터/구분자 토큰 방출
                            ch_data   <= UART_Dout;
                            ch_valid  <= 1'b1;
                            ch_is_sep <= (UART_Dout == 8'h2C); // ','

                            // 다음 바이트 읽기
                            if(!UART_Empty) begin
                                UART_RD_EN <= 1'b1;
                                st         <= S_POP;
                            end else begin
                                // 데이터가 더 없으면 대기. STX 기다리는 상태로 복귀하면,
                                // in_frame=1인데 WAIT_STX로 가면 '$'를 다시 기다리게 됨.
                                // 여기서는 안전하게 WAIT_STX로 복귀(스트림이 끊겨도 자연 복구).
                                st         <= S_WAIT_STX;
                            end
                        end
                    end
                end

                default: st <= S_WAIT_STX;
            endcase
        end
    end

endmodule
