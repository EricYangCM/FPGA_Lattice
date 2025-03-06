`include "i2c_slave_def.v"
`timescale 1 ns / 1 ns

module i2c_slave_simple #(
    parameter MEMORY_MAP_SIZE = 8'd50,
	parameter MAX_MEM_BURST_NUM = 8, 
	parameter INTQ_OPENDRAIN = "ON"  
	)
	(
    // I2C 신호
    inout  wire        SCL,
    inout  wire        SDA,
	
	
	output reg TP1,
	output reg TP2,
	
	output reg [7:0] LED
);

 // 내부 오실레이터 (12.09MHz) 생성
    wire clk;
    OSCH #(
        .NOM_FREQ("12.09")  
    ) internal_osc (
        .STDBY(1'b0),  
        .OSC(clk)      
    );

	parameter CLK_FREQ = 12090000;  

	// Reset 생성
	wire RST_N;
	ResetGen resetGen_inst(
	.clk_In(clk),
	.rst_n_1_out(RST_N)
	);
	
	/***********************************************************************
	 * WISHBONE 인터페이스 신호 (I2C와의 데이터 교환)
	 ***********************************************************************/
	reg  [7:0] wb_dat_i;
	reg        wb_stb_i;
	wire       wb_cyc_i = wb_stb_i;
	reg  [7:0] wb_adr_i;
	reg        wb_we_i;
	wire [7:0] wb_dat_o;
	wire       wb_ack_o;


	/***********************************************************************
	 * EFB I2C 모듈 인스턴스화
	 ***********************************************************************/
	wire rst_p = ~RST_N;
	I2C I2C_inst (
		.wb_clk_i (clk),
		.wb_rst_i (rst_p    ),
		.wb_dat_i (wb_dat_i ),
		.wb_stb_i (wb_stb_i ),
		.wb_cyc_i (wb_cyc_i ),
		.wb_adr_i (wb_adr_i ),
		.wb_we_i  (wb_we_i  ),
		.wb_dat_o (wb_dat_o ), 
		.wb_ack_o (wb_ack_o ),      
		.i2c1_scl (SCL      ),
		.i2c1_sda (SDA      )
	);

	/***********************************************************************
	 * I2C 상태 머신을 위한 변수
	 ***********************************************************************/
	reg [7:0] state;
	reg efb_flag;
	reg [7:0] testReg [0:30];
	reg [7:0] second_byte;
	reg [7:0] memory_addr;
	
	/***********************************************************************
	 * I2C 상태 머신 (State 0 ~ 8)
	 ***********************************************************************/
	 
	always @(posedge clk or negedge RST_N) begin 
		if (!RST_N) begin 
			state  <= `state0;
			efb_flag <= `LOW;
			wb_dat_i  <= 8'h00;
			wb_stb_i  <= 1'b0;
			wb_adr_i  <= 8'h00;
			wb_we_i   <= 1'b0;
			
			LED[7:0] <= 8'hFF;
			second_byte <= 8'h00;
			memory_addr <= 8'h00;
			
			testReg[0] <= 8'h12;
			testReg[1] <= 8'h34;
			testReg[2] <= 8'h56;
			testReg[3] <= 8'h78;
			testReg[4] <= 8'h9A;
			
			
		end  
		else begin  
			
			case(state)
				
				// I2C Enable
				`state0:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW ; 
						
						state <= `state1;
					end
					// Set I2C Enable
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `WRITE;
						wb_adr_i <= `MICO_EFB_I2C_CR;
						wb_dat_i <= `MICO_EFB_I2C_CR_I2CEN;
						wb_stb_i <= `HIGH; 
					end
				end
				
				
				// Clock Stretch Disable
				`state1:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						state <= `state2;
					end
					// Set I2C Enable
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `WRITE;
						wb_adr_i <= `MICO_EFB_I2C_CMDR;
						wb_dat_i <= `MICO_EFB_I2C_CMDR_CKSDIS;
						wb_stb_i <= `HIGH;
					end
				end
				
				// Wait for not busy
				`state2:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						if(wb_dat_o & `MICO_EFB_I2C_SR_BUSY) begin
							state <= `state2;
						end
						else begin
							state <= `state3;	// go to next
						end
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_SR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				
				// Discard data 1
				`state3:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						state <= `state4;	// go to next
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_RXDR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				// Discard data 2
				`state4:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						state <= `state5;	// go to next
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_RXDR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
			
				// Wait for TRRDY
				`state5:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						if(wb_dat_o & `MICO_EFB_I2C_SR_TRRDY) begin
							state <= `state6;  // go to next
						end
						else begin
							state <= `state5;	
						end
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_SR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				
				// Read Command
				`state6:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						memory_addr <= wb_dat_o;
						TP1 <= ~TP1;
						
						state <= `state7;	// go to next
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_RXDR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
			
			
				// Wait for TRRDY (2nd byte)
				`state7:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						if(wb_dat_o & `MICO_EFB_I2C_SR_TRRDY) begin
							state <= `state8;	// read second byte
						end
						
						// Stop
						else if((wb_dat_o & `MICO_EFB_I2C_SR_BUSY) == `ALL_ZERO) begin
							state <= `state1;  // go to first
						end
						
						
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_SR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				
				// Read Second Byte
				`state8:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						second_byte <= wb_dat_o;
						
						state <= `state9;	// go to next
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_RXDR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				// Read SR (Check Read or Write)
				`state9:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						
						if(wb_dat_o & `MICO_EFB_I2C_SR_SRW) begin
							state <= `state20;	// go to Read Process
						end
						else begin
							state <= `state10;	// go to Write Process
						end
						
						
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_SR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				
				
				
				
				// Write Process 1 - Write Second Byte
				`state10:begin
					testReg[memory_addr] <= second_byte;
					memory_addr <= memory_addr + 1;
					state <= `state11;
				end
				
				
				// Write Process 2 - Wait TRRDY
				`state11:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						if(wb_dat_o & `MICO_EFB_I2C_SR_TRRDY) begin
							state <= `state12;
						end
						
						// Stop
						else if((wb_dat_o & `MICO_EFB_I2C_SR_BUSY) == `ALL_ZERO) begin
							state <= `state1;  // go to first
						end
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_SR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				// Write Process 3 - Write Byte
				`state12:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						testReg[memory_addr] <= wb_dat_o;
						memory_addr <= memory_addr + 1;
						state <= `state11;	// go to next
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_RXDR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				
				// Read Process 1 - wait TRRDY
				`state20:begin
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						if(wb_dat_o & `MICO_EFB_I2C_SR_TRRDY) begin
							state <= `state21;
						end
						
						// Stop
						else if((wb_dat_o & `MICO_EFB_I2C_SR_BUSY) == `ALL_ZERO) begin
							state <= `state1;  // go to first
						end
						
						
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `READ;
						wb_adr_i <= `MICO_EFB_I2C_SR;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `HIGH;
					end
				end
				
				// Read Process 2 - Tx Data
				`state21:begin
					
					if(wb_ack_o && efb_flag) begin
						// Reset Signals
						efb_flag <= `LOW;
						wb_we_i <=  `LOW;
						wb_adr_i <= `ALL_ZERO;
						wb_dat_i <= `ALL_ZERO;
						wb_stb_i <= `LOW;
						
						memory_addr <= memory_addr + 1;
						state <= `state20;	// go to next
					end
					// Read SR
					else begin
						efb_flag <= `HIGH;
						wb_we_i <=  `WRITE;
						wb_adr_i <= `MICO_EFB_I2C_TXDR;
						wb_dat_i <= testReg[memory_addr];
						wb_stb_i <= `HIGH;
					end
					
				end
				
				
				
			endcase
			
		end  
	end
	

endmodule



