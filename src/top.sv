module top;
	reg clk = 0;
	always begin #1 clk = ~clk; end
	
	initial
		
	begin
		$dumpfile("top.vcd");
		$dumpvars(0, top);
		$display("test");
		#10
		$finish;
	end
endmodule
