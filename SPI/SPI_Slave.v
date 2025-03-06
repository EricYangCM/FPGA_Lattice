// LSB First, Clock = high, Phase = 2 edge (SPI Mode 3)
// Protocol : CS low -> W/R + 15-bit Memory Address -> Data
module SPI_Slave #(
parameter REGISTER_BYTE_SIZE = 400  // 내부 레지스터 바이트 사이즈
)
(
    input  wire        clk,      // FPGA 시스템 클럭
    input  wire        rst_n,    // 리셋
    
    input  wire        sck,      // SPI 클럭 (Master 제공)
    input  wire        cs,       // SPI Slave Select (LOW 활성)
    input  wire        mosi,     // Master → Slave 데이터
    output reg         miso,     // Slave → Master 데이터
	
    output reg [399:0] Register_Bits // 내부 레지스터
);

    reg        sck_prev;
    reg  [4:0] bit_cnt;       // 비트 카운터
    reg  [7:0] byte_buffer;   // 송수신 바이트 버퍼
    reg [14:0] addr_buffer;   // 어드레스 버퍼
    reg  [4:0] spi_state;     // SPI 상태 FSM
    reg        edge_toggle;
	
    reg sck_sync1, sck_sync2;
    wire sck_rising  = (sck_sync1 == 1'b1) && (sck_sync2 == 1'b0); // Rising Edge 감지
    wire sck_falling = (sck_sync1 == 1'b0) && (sck_sync2 == 1'b1); // Falling Edge 감지

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            miso       <= 0;
            sck_prev   <= 1;
            bit_cnt    <= 0;
            spi_state  <= 0;
            sck_sync1  <= 1'b1;
            sck_sync2  <= 1'b1;
            Register_Bits[399:0] <= 0; // 내부 레지스터 초기화
        end else begin
            sck_sync1 <= sck;      // 첫 번째 단계에서 SCK를 캡처
            sck_sync2 <= sck_sync1; // 두 번째 단계에서 안정화된 SCK를 저장

            // Chip Select 비활성화 시 초기화
            if (cs) begin
                bit_cnt    <= 0;
                sck_prev   <= 1; // Clock High when IDLE
                miso       <= 0;
                spi_state  <= 0;
                addr_buffer <= 0; // CS 비활성화 시 주소 초기화
            end else begin
                case (spi_state)
                    // Read Address & W/R Process
                    0: begin
                        miso <= 0; // slave out clear
						
                        // Falling Edge
                        if (sck_falling) begin
                            edge_toggle <= 0;
                        end
							
                        // Rising Edge에서 bit 읽기
                        if (sck_rising && (edge_toggle == 0)) begin
                            // 15-bit Address. LSB First
                            if (bit_cnt < 15) begin
                                addr_buffer <= {mosi, addr_buffer[14:1]}; // LSB First
                                bit_cnt     <= bit_cnt + 1;
                            end
							
                            // Read or Write
                            if (bit_cnt == 15) begin
                                // Read = 1
                                if (mosi) begin
                                    addr_buffer <= addr_buffer << 3;
                                    spi_state   <= 1; // Read Process로 이동
                                    edge_toggle <= 0; // clear at rising edge
                                end
                                // Write = 0
                                else begin
                                    addr_buffer <= addr_buffer << 3;
                                    spi_state   <= 2; // Write Process로 이동
                                    edge_toggle <= 1; // clear at falling edge
                                end
                            end
                        end
                    end

                    // Read Process
                    1: begin
                        // Falling Edge - Slave Bit Set
                        if (sck_falling && (edge_toggle == 0)) begin
                            miso       <= Register_Bits[addr_buffer]; // Set Bit. LSB First
                            addr_buffer <= addr_buffer + 1;           // Increase bit Address
                            edge_toggle <= 1;                         // clear at Rising edge
                        end
						
                        // Rising Edge - Master Read
                        if (sck_rising) begin
                            edge_toggle <= 0;
                        end
                    end
					
                    // Write Process
                    2: begin
                        // Rising Edge - Slave Bit Read
                        if (sck_rising && (edge_toggle == 0)) begin
                            Register_Bits[addr_buffer] <= mosi; // Save Bit. LSB First
                            addr_buffer <= addr_buffer + 1;     // Increase bit Address
                            edge_toggle <= 1;                   // clear at Falling edge
                        end
						
                        // Falling Edge - Master Bit Set
                        if (sck_falling) begin
                            edge_toggle <= 0;
                        end
                    end
                endcase

                // SCK Update
                sck_prev <= sck;
            end
        end
    end
endmodule
