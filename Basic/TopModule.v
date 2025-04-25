module TopModule(
	input wire osc_in,
    output reg TP
);


localparam CLK_Freq = 20000000;


// PLL for 20MHz
wire PLL_LOCK;
wire clk;
PLL PLL_inst(
	.CLKI(osc_in),
	.LOCK(PLL_LOCK),
	.CLKOP(clk)
);


// Reset
wire rst_n;
ResetGen ResetGen_inst(
	.clk_In(clk),
	.clk_lock(PLL_LOCK),
	.rst_n_1_out(rst_n)
);


endmodule
