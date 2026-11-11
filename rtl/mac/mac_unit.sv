`timescale 1ns/1ps

module mac_unit #(
	parameter int acc_width = 32,
	parameter int data_width = 8
)(
	input logic clk,
	input logic rst_n,

	input logic cfg_precision, // 0=INT8, 1=INT4

	input logic signed [data_width-1:0] weight_shift_in,
	output logic signed [data_width-1:0] weight_shift_out,
	input logic shift_en,
	input logic capture_en,

	input logic acc_clear,
	input logic valid_in,
	input logic signed [data_width-1:0] act_in,
	output logic signed [acc_width-1:0] acc_out
);


logic signed [data_width-1:0] weight_shift_reg;
always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		weight_shift_reg <= '0;
	else if (shift_en)
		weight_shift_reg <= weight_shift_in;
end
assign weight_shift_out = weight_shift_reg;


logic signed [data_width-1:0] weight_reg;
always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		weight_reg <= 0;
	else if (capture_en)
		weight_reg <= weight_shift_reg;
end


logic signed [data_width-1:0] mul_a, mul_b;
always_comb begin
	if (cfg_precision) begin
		mul_a = {{(data_width-4){act_in[3]}}, act_in[3:0]};
		mul_b = {{(data_width-4){weight_reg[3]}}, weight_reg[3:0]};
	end else begin
		mul_a = act_in;
		mul_b = weight_reg;
	end
end

logic signed [2*data_width-1:0] mul_result;
mulBW u_mul (
	.a(mul_a),
	.b(mul_b),
	.p(mul_result)
);

logic signed [acc_width-1:0] mul_result_ext;
assign mul_result_ext = {{(acc_width-2*data_width){mul_result[2*data_width-1]}}, mul_result};


logic signed [acc_width-1:0] acc_reg;


always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		acc_reg <= '0;
	else if (acc_clear)
		acc_reg <= '0;
	else if (valid_in)
		acc_reg <= acc_reg + mul_result_ext;
end

assign acc_out = acc_reg;
endmodule
