// -----------------------------------------------------------------------------
// UART_Rx_FIFO
// - UART 수신(8-N-1, 16x 오버샘플) + Lattice FIFO_DC(IPexpress) 통합 모듈
// - WrClock=RdClock=clk (동기식처럼 사용; 나중에 분리 가능)
// - FIFO Reset은 active-high라 ~rst_n 사용
// - FIFO 읽기: RdEn=1 → 다음 clk에 dout 유효 (Output Reg OFF 기준)
// -----------------------------------------------------------------------------
module UART_Rx_FIFO #(
    parameter integer CLK_HZ      = 48_000_000,
    parameter integer BAUD        = 115_200,
    parameter integer OVERSAMPLE  = 16,
    parameter integer READY_WIDTH = 4
)(
    input  wire       clk,
    input  wire       rst_n,

    // UART
    input  wire       uart_rx,

    // FIFO Read side (외부가 소비)
    input  wire       rd_en,       // 1클럭 팝 요청
    output wire [7:0] dout,        // RdEn 다음 클럭에 유효
    output wire       empty,       // 1이면 비어있음
    output wire       full,        // 1이면 가득참

    // 상태/디버그(옵션)
    output wire       almost_empty,
    output wire       almost_full,
    output reg  [31:0] overrun_cnt // full 상태에서 들어온 바이트 드롭 카운트
);

    // -----------------------
    // 1) UART 수신기
    // -----------------------
    wire [7:0] rx_data;
    wire       rx_ready;   // 1클럭 펄스(바이트 완료)
    wire       rx_done;    // 연속수신 종료(미사용 가능)
    wire       rx_ferr;    // stop bit 에러(미사용 가능)

    UART_RX #(
      .CLK_HZ(CLK_HZ),
      .BAUD(BAUD),
      .OVERSAMPLE(OVERSAMPLE),
      .READY_WIDTH(READY_WIDTH)
    ) u_rx (
      .clk        (clk),
      .rst_n      (rst_n),
      .rx_i       (uart_rx),
      .data       (rx_data),
      .byte_ready (rx_ready),
      .byte_done  (rx_done),
      .frame_err  (rx_ferr),
      .rx_busy    ()
    );

    // -----------------------
    // 2) FIFO_DC (IPexpress 생성 모듈 인스턴스)
    //    - 생성한 IP 모듈명으로 교체하세요. (예: FIFO_UART_RX)
    //    - Data/Q 폭은 8bit, 깊이(예:512)는 IP 설정에 따름
    // -----------------------
    wire [7:0] fifo_q;
    wire       fifo_empty, fifo_full;
    wire       fifo_aempty, fifo_afull;

    // 가득 찬 상태에서 들어오는 바이트는 드롭 + 카운트
    wire wr_en = rx_ready & ~fifo_full;

    // 오버런 카운트
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) overrun_cnt <= 32'd0;
        else if (rx_ready && fifo_full) overrun_cnt <= overrun_cnt + 1'b1;
    end

    // === 여기 모듈명을 당신 IP 이름으로 변경 ===
    FIFO_UART_RX u_fifo (
      .Data        (rx_data),     // [7:0]
      .Q           (fifo_q),      // [7:0]
      .WrClock     (clk),
      .RdClock     (clk),
      .WrEn        (wr_en),
      .RdEn        (rd_en),
      .Reset       (~rst_n),      // active-high
      .RPReset     (1'b0),
      .Empty       (fifo_empty),
      .Full        (fifo_full),
      .AlmostEmpty (fifo_aempty),
      .AlmostFull  (fifo_afull)
    );

    // -----------------------
    // 3) 외부로 노출
    // -----------------------
    assign dout         = fifo_q;
    assign empty        = fifo_empty;
    assign full         = fifo_full;
    assign almost_empty = fifo_aempty;
    assign almost_full  = fifo_afull;

endmodule
