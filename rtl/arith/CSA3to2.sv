`timescale 1ns/1ps
module CSA3to2 #(
	parameter int W = 16
)(
	input  logic [W-1:0] ina,
	input  logic [W-1:0] inb,
	input  logic [W-1:0] incin,
	output logic [W-1:0] sumout,
	output logic [W-1:0] coutt
);

	logic [W-1:0] carry_raw;

	assign sumout    = ina ^ inb ^ incin;
	assign carry_raw = (ina & inb) | (inb & incin) | (ina & incin);
	assign coutt      = carry_raw << 1;

endmodule
