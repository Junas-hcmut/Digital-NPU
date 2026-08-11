`timescale 1ns/1ps

module requant #(
	parameter int acc_width = 32,
	parameter int scale_width = 16,
	parameter int shift_width = 6,
	parameter int out_width = 8
	)(
	input logic clk,
        input logic rst_n,

input logic en,
input logic cfg_bypass,

input logic signed [acc_width-1:0] data_in,
input logic signed [acc_width-1:0] cfg_offset,
input logic signed [scale_width-1:0] cfg_scale,
input logic [shift_width-1:0] cfg_shift,

output logic signed [out_width-1:0] data_out,
output logic valid_out
);

logic signed [acc_width:0] sub_val;
assign sub_val = signed'(data_in) - signed'(cfg_offset);

localparam int prod_width = acc_width + 1 + scale_width;
logic signed [prod_width-1:0] prod_val;
assign pro_val = sub_val * signed'(cfg_scale);

logic signed [prod_width-1:0] shifted_val;
assign shifted_val = prod_val >>> cfg_shift;

localparam signed [prod_width-1:0] out_max = (1 <<< (out_width-1));

logic signed [out_width-1:0] sat_val;
always_comb besgin 
	if (shifted_val > out_max)
		sat_val = out_max[out_width-1:0];
	else if (shifted_val < out_min)
		sat_val = out_min[out_width-1:0];
	else 
		sat_val = shifted_val[out_width-1:0];
end 

logic signed [out_width-1:0] result_val;
assign result_val = cfg_bypass ? data_in[out_width-1:0] : sat_val;

always_ff @(posedge clk or negedge rst_n) begin 
	if (!rst_n) begin 
		data_out <= '0;
		valid_out <= 1'b0;
	end else if (en) begin 
		data_out <= result_val;
		valid_out <= 1'b1;
	end else begin
		valid_out <= 1'b0;
	end
end

endmodule 

