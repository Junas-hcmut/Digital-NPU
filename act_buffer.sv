`timescale 1ns/1ps
module act_buffer #(
	parameter int data_width = 8,
	parameter int depth = 256,
	parameter int addr_width = $clog2(depth)
	)(
		input logic clk,
		input logic rst_n,
//Ghi
		input logic wr_en,
		input logic [data_width-1:0] wr_data,
		output logic wr_ready
//Doc
                input logic rd_en,
		input logic [addr_width-1:0] rd_addr,
		output logic [data_width-1:0] rd_data,
		output logic rd_valid,

		input logic rd_retire_en,
		input logic [addr_width:0] rd_retire_cnt,

		output logic [addr_width:0] occupancy,
		output logic full,
		output logic empty
		);

		logic [data_width-1:0] mem [0:depth-1];
		logic [addr_width-1:0] wr_ptr;

		assign full = (occupancy == depth);
		assign empty = (occupancy == 0);
		assign wr_ready = ~full;

		always_ff @(posedge clk or negedge rst_n) begin
			if (!rst_n) begin
				wr_ptr <= '0;
			end else if (wr_en && wr_ready) begin
				mem[wr_ptr] <= wr_data;
				wr_ptr <= (wr_ptr == depth - 1) ? '0 : wr_ptr + 1'b1;
			end 
		end


		always_ff @(posedge clk or negedge rst_n) begin
			if(!rst_n) begin 
				rd_valid <= 1'b0;
				rd_data <= '0;
			end else begin 
				rd_valid <= rd_en;
				if(rd_en)
					rd_data <= mem[rd_addr];
			end
		end


		always_ff @(posedge clk or negedge rst_n) begin
			if (!rst_n) begin 
				occupancy <= '0;
			end else begin 
				case ({wr_en && wr_ready, rd_retire_en})
					2'b10: occupancy <= occupancy + 1'b1;
					2'b01: occupancy <= occupancy - rd_retire_cnt;
					2'b11: occupancy <= occupancy + 1'b1 - rd_retire_cnt;
					default: occupancy <= occupancy;
				endcase
			end
		end
		endmodule 

