module vga_data565(
	input wire [15:0] fifo_top,
	output wire [4:0] r, 
	output wire [5:0] g, 
	output wire [4:0] b
);

assign r = fifo_top[15:11];
assign g = fifo_top[10:5];
assign b = fifo_top[4:0];

endmodule

