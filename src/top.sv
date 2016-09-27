module top;
	reg clk = 0;
	always begin #1 clk = ~clk; end
endmodule
