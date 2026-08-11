`timescale 1ns/ps
module mac_system #(
	parameter int data_width = 8,
	parameter int acc_width = 32,
	parameter int num_pe = 16,
	parameter int num_array = 4
	)(
		input logic clk,
		input logic rst_n,
		input logic cfg_precision,

		// nap trong so
		input logic signed [data_width-1:0] weight_serial_in [num_array],
		output logic signed [data_width-1:0] weight_serial_out [num_array],
		input logic shift_en [num_array],
		input logic capture_en [num_array],

		//Tinh toan
		input logic acc_clear [num_array],
		input logic valid_in [num_array],
		input logic signed [data_width-1:0] act_in [num_array],
		output logic signed [acc_width-1:0] acc_out [num_array][num_pe]

		input logic output_load_en [num_array],
		input logic output_shift_en [num_array],
		output logic signed [acc_width-1:0] result_serial_out [num_array]
		);

genvar a;
generate
for (a=0; a < num_array; a++) begin: gen_array
	mac_chain #(
		.data_width(data_width),
		.acc_width(acc_width),
		.num_pe(num_pe)
		) u_array (
			.clk(clk),
			.rst_n(rst_n),
			.cfg_precision(cfg_precision)
			.weight_serial_in(weight_serial_in[a]),
			.weight_serial_out(weight_serial_out[a]),
			.shift_en(shift_en[a]),
			.capture_en(capture_en[a]),
			.acc_clear(acc_clear[a]),
			.act_in(act_in[a]),
			.valid_in(valid_in[a]),
			.acc_out(acc_out[a]),
                         
			.output_load_en(output_load_en[a]),
			.output_shift_en(output_shift_en[a]),
			.result_serial_out(result_serial_out[a])
			);
	end
endgenerate 
endmodule 

