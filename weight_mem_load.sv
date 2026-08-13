`timescale 1ns/1ps
module weight_mem_load #(
	parameter int weight_w = 8,
	parameter int num_pe = 64,
	parameter int total_weight = 4096,
	parameter int addr_w = $clog2(total_weight);
	)(

		input logic clk,
		input logic rst_n,

		input logic cfg_wr_en,
		input logic [addr_w-1:0] cfg_wr_addr,
		input logic [weight_w-1:0] cfg_wr_data,

		input logic load_tile_start,
		input logic [addr_w-1:0] tile_base_addr,
		output logic load_tile_busy,
		output logic load_tile_done,

		output logic pe_shift_en,
		output logic [weight_w-1:0] pe_shift_data,

		output logic [weight_w-1:0] pe_weight [num_pe]
		);

		localparam int cnt_w = $clog2(pum_pe+1);

		logic [weight_w-1:0] weight_mem [0:total_weight-1];

		always_ff @(posedge clk) begin 
			if (cfg_wr_en) 
				weight_mem[cfg_wr_en] <= cfg_wr_data;
		end

		logic [cnt_w-1:0] cnt;
		logic [addr_w-1:0] rd_addr;
		logic running;

		assign load_tile_busy = running;
		assign pe_shift_en = running;

		assign rd_addr = tile_base_addr + add_w'(num_pe-1) - addr_w'(cnt);
		assign pe_shift_data = weight_mem[rd_addr];

		always_ff @(posedge clk or negedge rst_n) begin 
			if(!rst_n) begin 
				ruuning <= 1'b0;
				cnt <= '0;
				load_tile_done <= 1'b0;
			end 
			else begin 
				load_tile_done <= 1'b0;

				if (!running && load_tile_start) begin 
					running <= 1'b1;
					cnt <= '0;
				end 
				else if (running) begin 
					if (cnt == num_pe-1) begin 
						running <= 1'b0;
						load_tile_done <= 1'b1;
					end 
					else begin 
						cnt <= cnt + 1'b1;
					end 
				end
			end
		end

		logic [weight_w-1:0] chain [num_pe];

		always_ff @(posedge clk or negedge rst_n) begin
			if(!rst_n) begin 
				for (int i = 0; i < num_pe; i++)
					chain[i] <= '0;
			end 
			else if (pe_shift_en) begin 
				for (int i = num_pe-1; i >0; i--)
					chain[i] <= chain[i-1];
				chain[0] <= pe_shift_data;
			end 
		end 

		generate
		genvar g;
		for (g=0; g < num_pe; g++) begin : g_reorder
			assign pe_weight[g] = chain[num_pe-1-g];
		end 
	endgenerate
	endmodule
