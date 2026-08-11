`timescale 1ns/1ps
module relu #(
	parameter int data_width = 32,
	parameter int lanes = 64
	)( 
		input logic clk,
		input logic rst_n,
		input logic en,
		input logic cfg_bypass,
		input logic signed [data_width-1:0] data_in [lanes],
		output logic signed [data_width-1:0] data_out [lanes],
		output logic valid_out
		);
		logic signed [data_width-1:0] lane_relu [lanes];
		always_comb begin
			for (int i = 0; i < lanes; i++) begin
				if (cfg_bypass) 
					lane_relu [i] = data_in [i];
				else if (data_in[i][data_width-1])
					lane_relu [i] = '0;
				else 
					lane_relu [i] = data_in[i];
		end
	end

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin 
			for (int k = 0; k < lanes; k++) 
				data_out[k] <= '0;
			valid_out <= 1'b0;
		end else if (en) begin 
			for (int k = 0; k < lanes; k++)
				data_out[k] <= lane_relu[k];
			valid_out <= 1'b1;
		end else begin 
			data_out[k] <= 1'b0;
		end
	end 
	endmodule 


