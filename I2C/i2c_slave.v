module I2C_Slave(
    inout wire SDA,
    input wire SCL,
    input wire clk,
    input wire rst_n
);

// Slave Address
localparam [6:0] SLAVE_ADDRESS = 7'b1000010;

parameter MEM_ADDR_MIN = 8'h00;
parameter MEM_ADDR_MAX = 8'hFF;  // 원하는 범위에 맞게 설정


// Internal Signals
reg SDA_drive_enable;
assign SDA = (SDA_drive_enable) ? 1'b0 : 1'bz;
wire SDA_In = sda_sync2;

// SCL, SDA 3단 동기화
reg scl_sync0, scl_sync1, scl_sync2;
reg sda_sync0, sda_sync1, sda_sync2;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_sync0 <= 1'b0;
        scl_sync1 <= 1'b0;
        scl_sync2 <= 1'b0;
		sda_sync0 <= 1'b0;
		sda_sync1 <= 1'b0;
		sda_sync2 <= 1'b0;
    end else begin
        scl_sync0 <= SCL;
        scl_sync1 <= scl_sync0;
        scl_sync2 <= scl_sync1;
		sda_sync0 <= SDA;
        sda_sync1 <= sda_sync0;
        sda_sync2 <= sda_sync1;
    end
end
wire SCL_Sync = scl_sync2;
wire SDA_Sync = sda_sync2;

// Edge Detectors
wire SDA_Rising;
EdgeDetector Edge_SDA_Rising(
    .clk(clk),
    .rst_n(rst_n),
    .signal_in(SDA_Sync),
    .edge_type(1'b1),
    .edge_pulse(SDA_Rising)
);

wire SDA_Falling;
EdgeDetector Edge_SDA_Falling(
    .clk(clk),
    .rst_n(rst_n),
    .signal_in(SDA_Sync),
    .edge_type(1'b0),
    .edge_pulse(SDA_Falling)
);

wire SCL_Rising;
EdgeDetector Edge_SCL_Rising(
    .clk(clk),
    .rst_n(rst_n),
    .signal_in(SCL_Sync),
    .edge_type(1'b1),
    .edge_pulse(SCL_Rising)
);

wire SCL_Falling;
EdgeDetector Edge_SCL_Falling(
    .clk(clk),
    .rst_n(rst_n),
    .signal_in(SCL_Sync),
    .edge_type(1'b0),
    .edge_pulse(SCL_Falling)
);

// I2C Conditions
wire start_condition_detected = (SCL_Sync == 1'b1) && (SDA_Falling == 1'b1);
wire stop_condition_detected  = (SCL_Sync == 1'b1) && (SDA_Rising == 1'b1);



reg [7:0] 	mem_addr;
wire [7:0] mem_dataOut;
reg [7:0] 	mem_dataIn;
reg 		mem_WR;

// Embedded SRAM
EBR_I2C EBR_I2C_inst(
	.ClockA(clk),
	.ClockB(clk),
	.ClockEnA(1'b1),
	.ClockEnB(1'b1),
	.ResetA(~rst_n),
	.ResetB(~rst_n),
	
	.DataInA(),
	.AddressA(),
	.WrA(1'b0),
	.QA(),
	
	.DataInB(mem_dataIn),
	.AddressB(mem_addr),
	.WrB(mem_WR),
	.QB(mem_dataOut)
);





// FSM Variables
localparam State_IDLE          = 0;
localparam State_SLA_W          = 1;
localparam State_MEM_ADDR      = 2;
localparam State_DATA_WRITE 	= 3;
localparam State_RS_SLA_R	   = 4;
localparam State_Data_READ     = 5;

reg [3:0] State;
reg [7:0] shift_reg;
reg [3:0] bit_cnt;

reg [7:0] tx_byte;       	// 현재 전송 중인 바이트
reg [2:0] read_phase;    	// 0: 초기화 1: 데이터 전송, 2: ACK 감지 대기

reg [3:0] write_phase;

reg [5:0] mem_update_cnt;	// EBR 업데이트 대기



// Main FSM
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        State <= State_IDLE;
        shift_reg <= 8'd0;
        bit_cnt <= 4'd0;
        SDA_drive_enable <= 1'b0;
		mem_WR <= 0;
    end else begin
        case (State)
            State_IDLE: begin
                SDA_drive_enable <= 1'b0;
				mem_WR <= 0;
				
                if (start_condition_detected) begin
                    State <= State_SLA_W;
                    shift_reg <= 8'd0;
                    bit_cnt <= 4'd0;
                end
            end


			// Slave Address + Write
            State_SLA_W: begin
                if (stop_condition_detected) begin
                    State <= State_IDLE;
                end 
				// Adress Data 8비트 받기, Rising Edge에서 저장하고 쉬프트
                else if ((bit_cnt < 4'd8) && (SCL_Rising)) begin
					shift_reg <= {shift_reg[6:0], SDA_In};
					bit_cnt <= bit_cnt + 1;
				end
				// Address Data 8비트 수신 완료 후 Falling Edge에서 ACK 판단
			    else if ((bit_cnt == 4'd8) && (SDA_drive_enable == 1'b0) && (SCL_Falling)) begin
					
					// Set ACK at SCL Falling Edge. (Valid Slave Address & Write Command)
                    if ((shift_reg[7:1] == SLAVE_ADDRESS) && (shift_reg[0] == 1'b0)) begin
                        SDA_drive_enable <= 1'b1; // ACK 드라이브
                    end
					// Set NACAK
					else begin
						State <= State_IDLE;
					end
				end
				// clear ACK and go to next step.
				else if ((SDA_drive_enable) && (SCL_Falling)) begin
					SDA_drive_enable <= 1'b0;
					bit_cnt <= 4'd0;
					shift_reg <= 8'd0;
					State <= State_MEM_ADDR;
				end
            end
			


			// Memory Address Check
            State_MEM_ADDR: begin
                if (stop_condition_detected) begin
					State <= State_IDLE;
				end 
				else if ((bit_cnt < 8) && (SCL_Rising)) begin
					shift_reg <= {shift_reg[6:0], SDA_In};
					bit_cnt <= bit_cnt + 1;
				end 
				else if ((bit_cnt == 8) && (SDA_drive_enable == 1'b0) && (SCL_Falling)) begin
					// 주소 유효성 검사
					if ((shift_reg >= MEM_ADDR_MIN) && (shift_reg <= MEM_ADDR_MAX)) begin
						mem_addr <= shift_reg;
						SDA_drive_enable <= 1'b1;  // ACK
					end else begin
						State <= State_IDLE; // NACK
					end
				end 
				else if (SDA_drive_enable && SCL_Falling) begin
					SDA_drive_enable <= 1'b0;		// ACK Release
					bit_cnt <= 0;
					shift_reg <= 8'd0;
					write_phase <= 0;
					State <= State_DATA_WRITE;
				end
            end
			
			
			// Data Write
			State_DATA_WRITE: begin
				
				if (stop_condition_detected) begin
					State <= State_IDLE;
				end
				else if(start_condition_detected) begin
					State <= State_RS_SLA_R;	// Repeated Start
					bit_cnt <= 0;
					SDA_drive_enable <= 0;
				end
				
				// 초기화
				else if(write_phase == 0) begin
					mem_dataIn <= 0;
					mem_WR <= 1'b0;
					SDA_drive_enable <= 1'b0;
					write_phase <= 1;
					bit_cnt <= 0;
					shift_reg <= 0;
				end
				// 데이터 수신
				else if ((bit_cnt < 8) && (SCL_Rising) && (write_phase == 1)) begin
					shift_reg <= {shift_reg[6:0], SDA_In};
					bit_cnt <= bit_cnt + 1;
				end 
				// 데이터 수신 완료
				else if ((bit_cnt == 8) && (SCL_Falling) && (write_phase == 1)) begin
					SDA_drive_enable <= 1'b1;	// ACK
					
					mem_dataIn <= shift_reg;	// Set Data to EBR
					mem_WR <= 1'b1;				// Write
					
					write_phase <= 2;
				end
				// ACK 후 다음 Falling Edge. Master가 데이터 세팅 중
				else if ((write_phase == 2) && (SCL_Falling)) begin
					write_phase <= 0;
					mem_addr <= mem_addr + 1;
				end
				
				
				
			end



            State_RS_SLA_R: begin
				if (stop_condition_detected) begin
					State <= State_IDLE;
				end
				// Adress Data 8비트 받기, Rising Edge에서 저장하고 쉬프트
                else if ((bit_cnt < 4'd8) && (SCL_Rising)) begin
					shift_reg <= {shift_reg[6:0], SDA_In};
					bit_cnt <= bit_cnt + 1;
				end
				// Address Data 8비트 수신 완료 후 Falling Edge에서 ACK 판단
			    else if ((bit_cnt == 4'd8) && (SDA_drive_enable == 1'b0) && (SCL_Falling)) begin
					
					// Read
					if(shift_reg[0] == 1) begin
						SDA_drive_enable <= 1'b1;	// ACK
					end
					else begin
						State <= State_IDLE;
					end
				end
				// Rising 에서 ACK release하고 넘어가기
				else if(SDA_drive_enable && SCL_Falling) begin
					read_phase <= 0;
					State <= State_Data_READ;
				end
            end


            State_Data_READ: begin
				if (stop_condition_detected) begin
                    State <= State_IDLE;
                end
				
				// 1: 초기화
				else if(read_phase == 0) begin
					//SDA_drive_enable <= 1'b0;	// ACK release
					mem_WR <= 1'b0;	
					mem_update_cnt <= 0;		// Clear Memory Update Counter
					read_phase <= 1;
				end
				
				// EBR Memody Update 대기 5 clock
				else if(mem_update_cnt < 5) begin
					mem_update_cnt <= mem_update_cnt + 1;
				end
				// EBR Memory Update Done
				else if(mem_update_cnt == 5) begin
					mem_update_cnt <= mem_update_cnt + 1;
					
					// Data Latch
					tx_byte <= ~mem_dataOut;
				end
				else if(mem_update_cnt == 6) begin
					mem_update_cnt <= mem_update_cnt + 1;
					
					read_phase <= 2;	// Data Ready.
					SDA_drive_enable <= tx_byte[7 - bit_cnt];	// Set First bit.
					bit_cnt <= 1;
				end
				

				// 2: 데이터 전송 중
				else if (read_phase == 2) begin
					if (bit_cnt < 8 && SCL_Falling) begin
						SDA_drive_enable <= tx_byte[7 - bit_cnt];
						bit_cnt <= bit_cnt + 1;
					end
					// byte set done. Master Set ACK
					else if(bit_cnt == 8 && SCL_Falling) begin
						read_phase <= 3;       	// ACK 감지 단계로 전환
						SDA_drive_enable <= 1'b0;	// SDA Release
					end
				end

				// 3: 마스터 ACK 감지
				else if (read_phase == 3) begin
					
					if (SCL_Rising) begin
						if (SDA_In == 1'b0) begin
							// 마스터 ACK → 다음 바이트 전송 준비
							mem_addr <= mem_addr + 1;
							read_phase <= 4;
							
						end else begin
							// 마스터 NACK → 전송 종료
							State <= State_IDLE;
						end
					end
				end
				
				// 4: 마스터 ACK 후 Falling Edge 기다린 후 초기화
				else if (read_phase == 4) begin
					if(SCL_Falling) begin
						read_phase <= 0;
					end
				end
				
            end


            default: begin
                State <= State_IDLE;
            end

        endcase
    end
end

endmodule
