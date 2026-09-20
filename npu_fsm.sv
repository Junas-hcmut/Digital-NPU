`timescale 1ns/1ps
module npu_fsm #(
	parameter int data_width  = 8,
	parameter int cnt_width   = 16,
	parameter int num_pe      = 16,
	parameter int act_addr_w  = 10,   
	parameter int wgt_addr_w  = 12,   
	parameter int pe_cnt_w    = 5     
)(
	input  logic clk,
	input  logic rst_n,

	input  logic                 start,
	input  logic [cnt_width-1:0] cfg_reduction_len,
	
	input  logic                   wload_done0,
	input  logic                   act_rd_valid,
	input  logic [data_width-1:0]  act_rd_data,
	input  logic                   relu_valid,
	input  logic                   requant_valid0,
	
	output logic busy,
	output logic done,          
	output logic                        wload_start,
	output logic [wgt_addr_w-1:0]       wload_base,     
	output logic                        mac_capture_en,
	output logic                        mac_acc_clear,
	output logic                        mac_valid_in,
	output logic signed [data_width-1:0] act_hold,
	output logic                        mac_out_load_en,
	output logic                        mac_out_shift_en,
	output logic                   act_rd_en,
	output logic [act_addr_w-1:0]  act_rd_addr,
	output logic                   act_rd_retire_en,
	output logic relu_en,
	output logic requant_en,

	output logic [cnt_width-1:0] red_step,
	output logic [pe_cnt_w-1:0]  out_pe_cnt
);
	typedef enum logic [3:0] {
		S_IDLE, S_SHIFT_W, S_WAIT_SHIFT_W, S_CAPTURE_W,
		S_FETCH_ACT, S_WAIT_ACT, S_MAC_ACC,
		S_RED_DONE_CHK,
		S_OUT_LOAD, S_OUT_SHIFT, S_WAIT_RELU, S_WAIT_REQUANT, S_OUT_DONE_CHK,
		S_DONE
	} state_t;
	state_t state, state_n;
	assign busy = (state != S_IDLE);
	assign done = (state == S_DONE);
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) state <= S_IDLE;
		else        state <= state_n;
	end
 	always_comb begin
		state_n = state;
		unique case (state)
			S_IDLE: begin
				if (start) state_n = S_SHIFT_W;
				else       state_n = S_IDLE;
			end
			S_SHIFT_W:       state_n = S_WAIT_SHIFT_W;
			S_WAIT_SHIFT_W: begin
				if (wload_done0) state_n = S_CAPTURE_W;
				else              state_n = S_WAIT_SHIFT_W;
			end
			S_CAPTURE_W:     state_n = S_FETCH_ACT;
			S_FETCH_ACT:     state_n = S_WAIT_ACT;
			S_WAIT_ACT: begin
				if (act_rd_valid) state_n = S_MAC_ACC;
				else               state_n = S_WAIT_ACT;
			end
			S_MAC_ACC:       state_n = S_RED_DONE_CHK;
			S_RED_DONE_CHK: begin
				if (red_step == cfg_reduction_len-1) state_n = S_OUT_LOAD;
				else                                  state_n = S_SHIFT_W;
			end
			S_OUT_LOAD:      state_n = S_OUT_SHIFT;
			S_OUT_SHIFT:     state_n = S_WAIT_RELU;
			S_WAIT_RELU: begin
				if (relu_valid) state_n = S_WAIT_REQUANT;
				else              state_n = S_WAIT_RELU;
			end
			S_WAIT_REQUANT: begin
				if (requant_valid0) state_n = S_OUT_DONE_CHK;
				else                  state_n = S_WAIT_REQUANT;
			end
			S_OUT_DONE_CHK: begin
				if (out_pe_cnt == num_pe-1) state_n = S_DONE;
				else                          state_n = S_OUT_SHIFT;
			end
			S_DONE:          state_n = S_IDLE;
			default:         state_n = S_IDLE;
		endcase
	end

	assign wload_start      = (state == S_SHIFT_W);
	assign wload_base       = wgt_addr_w'(red_step) * wgt_addr_w'(num_pe);
	assign mac_capture_en   = (state == S_CAPTURE_W);
	assign mac_acc_clear    = (state == S_SHIFT_W) && (red_step == 0);
	assign mac_valid_in     = (state == S_MAC_ACC);
	assign mac_out_load_en  = (state == S_OUT_LOAD);
	assign mac_out_shift_en = (state == S_OUT_SHIFT);
	assign act_rd_en         = (state == S_FETCH_ACT);
		assign act_rd_addr       = act_base + act_addr_w'(red_step);
	assign act_rd_retire_en  = (state == S_MAC_ACC);
	assign relu_en    = (state == S_OUT_SHIFT);
	assign requant_en = (state == S_WAIT_RELU) && relu_valid;

	logic [act_addr_w-1:0] act_base;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			red_step   <= '0;
			out_pe_cnt <= '0;
			act_hold   <= '0;
			act_base   <= '0;
		end else begin
			unique case (state)
				S_IDLE: if (start) begin
					red_step   <= '0;
					out_pe_cnt <= '0;
				end
				S_WAIT_ACT: if (act_rd_valid)
					act_hold <= act_rd_data;
				S_RED_DONE_CHK: if (red_step != cfg_reduction_len-1)
					red_step <= red_step + 1'b1;
				S_OUT_DONE_CHK: if (out_pe_cnt != num_pe-1)
					out_pe_cnt <= out_pe_cnt + 1'b1;
				S_DONE:
					act_base <= act_base + act_addr_w'(cfg_reduction_len);
				default: ;
			endcase
		end
	end
endmodule
