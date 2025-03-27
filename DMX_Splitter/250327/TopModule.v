module Top_Module (
    input wire clk_in/*synthesis syn_force_pads=1 syn_noprune=1 */,
	
	input wire cs/*synthesis syn_force_pads=1 syn_noprune=1 */,
	input wire mosi /*synthesis syn_force_pads=1 syn_noprune=1 */,
	input wire sck/*synthesis syn_force_pads=1 syn_noprune=1 */,
	output wire miso,
	
	
	
	input wire [1:0] DMX_Input_Signals /*synthesis syn_force_pads=1 syn_noprune=1 */,		// 2개의 DMX 입력 핀.
	output wire [9:0] DMX_Outputs_Signals,		// 10개의 DMX 출력 핀
	
	output wire [1:0] DMX_Input_DE,
	output wire [9:0] DMX_Output_DE,
	
	output wire [1:0] Input_Term_Res_EN,
	
	output wire [1:0] LED_Input_Green,
	output wire [1:0] LED_Input_Yellow,
	
	output wire [9:0] LED_Output_Green,
	output wire[9:0] LED_Output_Yellow
);


	// PLL
	wire clk, clk_lock;
	PLL PLL_inst(
	.CLKI(clk_in),
	.CLKOP(clk),
	.LOCK(clk_lock)
	);
	

	// Reset
	ResetGen reset_gen_inst(
	.clk_In(clk),
	.rst_n_1_out(rst_n),
	.clk_lock(clk_lock)
	);


	
	
	// SPI Interface Register
	localparam	SPI_REGISTER_BYTE_SIZE = 96;
	wire [(SPI_REGISTER_BYTE_SIZE*8)-1:0] Registers;
	SPI_Slave #(
		.REGISTER_BYTE_SIZE(SPI_REGISTER_BYTE_SIZE)
	)
	SPI_Slave_inst(
	.clk(clk),
	.rst_n(rst_n),
	.sck(sck),
	.cs(cs),
	.mosi(mosi),
	.miso(miso),
	.Register_Bits(Registers)
	);
	
	
	
	
	
	// DMX Register Map assignments
	assign DMX_OUT_1_TX_EN = Registers[0];
	assign DMX_OUT_1_SEL = Registers[1];
	assign DMX_OUT_1_FREQ_MODE = Registers [3:2];
	assign DMX_OUT_2_TX_EN = Registers[8];
	assign DMX_OUT_2_SEL = Registers[9];
	assign DMX_OUT_2_FREQ_MODE = Registers [11:10];
	assign DMX_OUT_3_TX_EN = Registers[16];
	assign DMX_OUT_3_SEL = Registers[17];
	assign DMX_OUT_3_FREQ_MODE = Registers [19:18];
	assign DMX_OUT_4_TX_EN = Registers[24];
	assign DMX_OUT_4_SEL = Registers[25];
	assign DMX_OUT_4_FREQ_MODE = Registers [27:26];
	assign DMX_OUT_5_TX_EN = Registers[32];
	assign DMX_OUT_5_SEL = Registers[33];
	assign DMX_OUT_5_FREQ_MODE = Registers [35:34];
	assign DMX_OUT_6_TX_EN = Registers[40];
	assign DMX_OUT_6_SEL = Registers[41];
	assign DMX_OUT_6_FREQ_MODE = Registers [43:42];
	assign DMX_OUT_7_TX_EN = Registers[48];
	assign DMX_OUT_7_SEL = Registers[49];
	assign DMX_OUT_7_FREQ_MODE = Registers [51:50];
	assign DMX_OUT_8_TX_EN = Registers[56];
	assign DMX_OUT_8_SEL = Registers[57];
	assign DMX_OUT_8_FREQ_MODE = Registers [59:58];
	assign DMX_OUT_9_TX_EN = Registers[64];
	assign DMX_OUT_9_SEL = Registers[65];
	assign DMX_OUT_9_FREQ_MODE = Registers [67:66];
	assign DMX_OUT_10_TX_EN = Registers[72];
	assign DMX_OUT_10_SEL = Registers[73];
	assign DMX_OUT_10_FREQ_MODE = Registers [75:74];
	
	
	// DMX Common Parameters
	localparam DMX_BUFFER_SIZE = 8;
	localparam CLOCK_FREQ = 20_000_000;		// 20 MHz
	
	
	// DMX Input A
	wire [(8*DMX_BUFFER_SIZE)-1:0] DMX_Data_A;
	wire [9:0] DMX_N_Of_Data_A;
	wire DMX_Signal_EN_A;
	DMX_Input_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_In_A(
		.clk(clk),
		.rst_n(rst_n),
		
		// To Port
		.DMX_Input_Signal(DMX_Input_Signals[0]),
		.DE(DMX_Input_DE[0]),
		
		// DMX Input Data A
		.DMX_Data(DMX_Data_A),
		.N_Of_Data(DMX_N_Of_Data_A),
		.Signal_Receiving_LED(LED_Input_Green[0]),
		
		.TP(LED_Output_Green)
	);
	
	/*
	// DMX Input B
	wire [(8*DMX_BUFFER_SIZE)-1:0] DMX_Data_B;
	wire [9:0] DMX_N_Of_Data_B;
	wire DMX_Signal_EN_B;
	DMX_Input_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_In_B(
		.clk(clk),
		.rst_n(rst_n),
		
		// To Port
		.DMX_Input_Signal(DMX_Input_Signals[1]),
		.DE(DMX_Input_DE[1]),
		
		// DMX Input Data B
		.DMX_Data(DMX_Data_B),
		.N_Of_Data(DMX_N_Of_Data_B),
		.Signal_EN(DMX_Signal_EN_B),
		.Signal_Receiving_LED(LED_Input_Yellow[1])
	);
	*/
	
	/*
	// DMX Output #1
	wire DMX_OUT_1_TX_EN;
	wire DMX_OUT_1_SEL;
	wire [1:0] DMX_OUT_1_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_1(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_1_TX_EN),
		.DMX_SEL(DMX_OUT_1_SEL),
		.FREQ_MODE(DMX_OUT_1_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[0]),
		.DMX_Output_Signal(DMX_Outputs_Signals[0])
	);

	// DMX Output #2
	wire DMX_OUT_2_TX_EN;
	wire DMX_OUT_2_SEL;
	wire [1:0] DMX_OUT_2_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_2(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_2_TX_EN),
		.DMX_SEL(DMX_OUT_2_SEL),
		.FREQ_MODE(DMX_OUT_2_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[1]),
		.DMX_Output_Signal(DMX_Outputs_Signals[1])
	);

	// DMX Output #3
	wire DMX_OUT_3_TX_EN;
	wire DMX_OUT_3_SEL;
	wire [1:0] DMX_OUT_3_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_3(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_3_TX_EN),
		.DMX_SEL(DMX_OUT_3_SEL),
		.FREQ_MODE(DMX_OUT_3_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[2]),
		.DMX_Output_Signal(DMX_Outputs_Signals[2])
	);



	// DMX Output #4
	wire DMX_OUT_4_TX_EN;
	wire DMX_OUT_4_SEL;
	wire [1:0] DMX_OUT_4_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_4(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_4_TX_EN),
		.DMX_SEL(DMX_OUT_4_SEL),
		.FREQ_MODE(DMX_OUT_4_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[3]),
		.DMX_Output_Signal(DMX_Outputs_Signals[3])
	);


	// DMX Output #5
	wire DMX_OUT_5_TX_EN;
	wire DMX_OUT_5_SEL;
	wire [1:0] DMX_OUT_5_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_5(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_5_TX_EN),
		.DMX_SEL(DMX_OUT_5_SEL),
		.FREQ_MODE(DMX_OUT_5_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[4]),
		.DMX_Output_Signal(DMX_Outputs_Signals[4])
	);
	
	
	// DMX Output #6
	wire DMX_OUT_6_TX_EN;
	wire DMX_OUT_6_SEL;
	wire [1:0] DMX_OUT_6_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_6(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_6_TX_EN),
		.DMX_SEL(DMX_OUT_6_SEL),
		.FREQ_MODE(DMX_OUT_6_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[5]),
		.DMX_Output_Signal(DMX_Outputs_Signals[5])
	);
	
	
	// DMX Output #7
	wire DMX_OUT_7_TX_EN;
	wire DMX_OUT_7_SEL;
	wire [1:0] DMX_OUT_7_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_7(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_7_TX_EN),
		.DMX_SEL(DMX_OUT_7_SEL),
		.FREQ_MODE(DMX_OUT_7_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[6]),
		.DMX_Output_Signal(DMX_Outputs_Signals[6])
	);
	
	
	// DMX Output #8
	wire DMX_OUT_8_TX_EN;
	wire DMX_OUT_8_SEL;
	wire [1:0] DMX_OUT_6_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_8(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_8_TX_EN),
		.DMX_SEL(DMX_OUT_8_SEL),
		.FREQ_MODE(DMX_OUT_8_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[7]),
		.DMX_Output_Signal(DMX_Outputs_Signals[7])
	);
	
	
	// DMX Output #9
	wire DMX_OUT_9_TX_EN;
	wire DMX_OUT_9_SEL;
	wire [1:0] DMX_OUT_9_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_9(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_9_TX_EN),
		.DMX_SEL(DMX_OUT_9_SEL),
		.FREQ_MODE(DMX_OUT_9_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[8]),
		.DMX_Output_Signal(DMX_Outputs_Signals[8])
	);
	
	
	// DMX Output #10
	wire DMX_OUT_10_TX_EN;
	wire DMX_OUT_10_SEL;
	wire [1:0] DMX_OUT_10_FREQ_MODE;
	DMX_Output_Module #(
		.CLK_FREQ(CLOCK_FREQ),
		.DMX_BUFFER_SIZE(DMX_BUFFER_SIZE)
	)DMX_Out_10(
		.clk(clk),
		.rst_n(rst_n),
		
		// Data Input A
		.DMX_Data_A(DMX_Data_A),
		.N_Of_Bytes_A(DMX_N_Of_Data_A),
		.Signal_Enabled_A(DMX_Signal_EN_A),
		
		// Data Input B
		.DMX_Data_B(DMX_Data_B),
		.N_Of_Bytes_B(DMX_N_Of_Data_B),
		.Signal_Enabled_B(DMX_Signal_EN_B),
		
		// Tx Control Registers
		.TX_EN(DMX_OUT_10_TX_EN),
		.DMX_SEL(DMX_OUT_10_SEL),
		.FREQ_MODE(DMX_OUT_10_FREQ_MODE),
		
		// To Port
		.DE(DMX_Output_DE[9]),
		.DMX_Output_Signal(DMX_Outputs_Signals[9])
	);
	
*/





endmodule
