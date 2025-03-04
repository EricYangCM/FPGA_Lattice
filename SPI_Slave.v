// Clock = high, Phase = 2 edge (SPI Mode 3)
module SPI_Slave(
    input  wire clk,      // FPGA 시스템 클럭
    input  wire rst_n,    // 리셋
    
    input  wire sck,      // SPI 클럭 (Master 제공)
    input  wire cs,       // SPI Slave Select (LOW 활성)
    input  wire mosi,     // Master → Slave 데이터
    output reg  miso     // Slave → Master 데이터
);

    reg sck_prev;
    reg [3:0] bit_cnt;      // 비트 카운터
    reg [7:0] byte_buffer;  // 송수신 바이트 버퍼
    reg [7:0] addr_buffer;  // 어드레스 버퍼
    reg [4:0] spi_state;    // SPI 상태 FSM
	reg edge_toggle;

    integer i;
    reg [7:0] Registers [0:49]; // 내부 레지스터
	
	reg sck_sync1, sck_sync2;
	wire sck_rising = (sck_sync1 == 1'b1) && (sck_sync2 == 1'b0); // Rising Edge 감지
	wire sck_falling = (sck_sync1 == 1'b0) && (sck_sync2 == 1'b1); // Falling Edge 감지

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            miso <= 0;
            sck_prev <= 1;
            bit_cnt <= 0;
            spi_state <= 0;

			sck_sync1 <= 1'b1;
			sck_sync2 <= 1'b1;
			
			
            // 내부 레지스터 초기화
            for (i = 0; i < 10; i = i + 1) begin
                Registers[i] = 8'h08;
            end
			
			
            for (i = 10; i < 50; i = i + 1) begin
                Registers[i] = 8'h00;
            end

        end else begin
			
			sck_sync1 <= sck;  // 첫 번째 단계에서 SCK를 캡처
			sck_sync2 <= sck_sync1; // 두 번째 단계에서 안정화된 SCK를 저장
		
			
            // Chip Select 비활성화 시 초기화
            if (cs) begin
                bit_cnt <= 0;
                sck_prev <= 1; // Clock High when IDLE
                miso <= 0;
                spi_state <= 0;
                addr_buffer <= 0; // CS 비활성화 시 주소 초기화
			
			
            end else begin
                case (spi_state)
                    // Read Address Process
                    0: begin
                        miso <= 0; // slave out clear
						
						// Falling Edge
						if(sck_falling) begin
							edge_toggle <= 0;
						end
							
                        // Rising Edge에서 bit 읽기
                        if (sck_rising && (edge_toggle == 0)) begin
                            
							// Bits Reading
							if (bit_cnt < 7) begin
                                addr_buffer <= {addr_buffer[6:0], mosi}; // Shift 방식
                                bit_cnt <= bit_cnt + 1;
								edge_toggle <= 1;	// clear at falling edge
                            end 
							
							// Bits Read Done
							else if (bit_cnt == 7) begin
                                bit_cnt <= 0; // 비트 카운터 초기화
								
								// Read = 1
								if(mosi) begin
									byte_buffer <= Registers[addr_buffer];		// set byte to Transmit Buffer
									addr_buffer <= addr_buffer + 1;
									spi_state <= 1; // Read Process로 이동
									edge_toggle <= 0;	// clear at rising edge
								end
								
								// Write = 0
								else begin
									byte_buffer <= 0;	// byte buffer 비우기
									spi_state <= 2; // Write Process로 이동
									edge_toggle <= 1;	// clear at falling edge
								end
								
                            end
							
                        end
                    end


					// Read Process
                    1: begin
						
						// Falling Edge - Slave Bit Set
						if(sck_falling && (edge_toggle == 0)) begin
							
							if(bit_cnt < 7) begin
								miso <= byte_buffer[7]; 					// MSB부터 전송
								byte_buffer <= {byte_buffer[6:0], 1'b0}; 	// Left Shift
								bit_cnt <= bit_cnt + 1;
							end
							// 1 byte transmit done
							else if(bit_cnt == 7) begin
								miso <= byte_buffer[7]; 					// last bit 전송
								byte_buffer <= Registers[addr_buffer];		// set new byte to Transmit Buffer
								addr_buffer <= addr_buffer + 1;
								bit_cnt <= 0;
							end
							
							edge_toggle <= 1;							// clear at Rising edge
						end
						
						
						// Rising Edge - Master Read
						if(sck_rising) begin
							edge_toggle <= 0;
						end
						
                    end
					
					
					
					// Write Process
                    2: begin
						
						// Rising Edge - Slave Bit Read
						if(sck_rising && (edge_toggle == 0)) begin
							
							if(bit_cnt < 8) begin
								byte_buffer <= {byte_buffer[6:0], mosi}; // Shift하면서 MOSI 저장
								bit_cnt <= bit_cnt + 1;
							end
							
							edge_toggle <= 1;							// clear at Falling edge
						end
						
						// 1 byte receive done
						if(bit_cnt == 8) begin
							Registers[addr_buffer] <= byte_buffer;
							addr_buffer <= addr_buffer + 1;
							bit_cnt <= 0;
						end
						
						// Falling Edge - Master Bit Set
						if(sck_falling) begin
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
