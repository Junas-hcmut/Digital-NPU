`timescale 1ns/1ps
//     mac_unit.
module mac_chain #(
	parameter int acc_width = 32,
	parameter int data_width = 8,
	parameter int num_pe = 16
	)(
		input logic clk,
		input logic rst_n,

		input logic cfg_precision, 

		input logic signed [data_width-1:0] weight_serial_in,
		output logic signed [data_width-1:0] weight_serial_out,
		input logic shift_en,
		input logic capture_en,

		input logic acc_clear,
		input logic valid_in,
		input logic signed [data_width-1:0] act_in,
		output logic signed [acc_width-1:0] acc_out[num_pe],

		input logic output_load_en,
		input logic output_shift_en,
		output logic signed [acc_width-1:0] result_serial_out
		);

		logic signed [data_width-1:0] chain_link[num_pe+1];
		assign chain_link[0] = weight_serial_in;
		assign weight_serial_out = chain_link[num_pe];

		genvar i;
		generate
		for (i=0; i < num_pe; i++) begin : gen_pe
			mac_unit #(
				.data_width(data_width),
				.acc_width(acc_width)
				) u_pe (
				.clk(clk),
				.rst_n(rst_n),
				.cfg_precision(cfg_precision),
				.shift_en(shift_en),
				.capture_en(capture_en),
				.acc_clear(acc_clear),
				.act_in(act_in),
				.valid_in(valid_in),
				.weight_shift_in(chain_link[i]),
				.weight_shift_out(chain_link[i+1]),
				.acc_out(acc_out[i])
				);
			end
		endgenerate

		logic signed [acc_width-1:0] out_shift_reg [num_pe];
		always_ff @(posedge clk or negedge rst_n) begin
			if (!rst_n) begin
				for (int k=0; k < num_pe; k++)
					out_shift_reg[k] <= '0;
			end else if (output_load_en) begin
				for (int k = 0; k < num_pe; k++)
					out_shift_reg[k] <= acc_out[k];
			end else if (output_shift_en) begin
				for (int k=0; k < num_pe - 1; k++)
					out_shift_reg[k] <= out_shift_reg[k+1];
				out_shift_reg [num_pe-1] <= '0;
			end
		end
		assign result_serial_out = out_shift_reg[0];

	endmodule
