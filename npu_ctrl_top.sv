`timescale 1ns/1ps

module npu_ctrl_top #(
	parameter int data_width  = 8,
	parameter int acc_width   = 32,
	parameter int out_width   = 8,
	parameter int num_pe      = 16,
	parameter int num_array   = 4,
	parameter int act_depth   = 1024,
	parameter int wgt_depth   = 4096,   
	parameter int cnt_width   = 16,

		parameter int act_addr_w = $clog2(act_depth),
	parameter int wgt_addr_w = $clog2(wgt_depth),
	parameter int pe_cnt_w   = $clog2(num_pe+1)
)(
	input logic clk,
	input logic rst_n,

	
	input  logic              start,
	output logic              busy,
	output logic              done,
	input  logic [cnt_width-1:0] cfg_reduction_len,
	input  logic              cfg_precision,    


	input  logic                  act_wr_en,
	input  logic [data_width-1:0] act_wr_data,
	output logic                  act_wr_ready,

		input  logic [num_array-1:0]                    cfg_wgt_wr_en,
	input  logic [num_array-1:0][wgt_addr_w-1:0]     cfg_wgt_wr_addr,
	input  logic [num_array-1:0][data_width-1:0]     cfg_wgt_wr_data,


	input  logic                     cfg_relu_bypass,
	input  logic                     cfg_requant_bypass,
	input  logic signed [acc_width-1:0] cfg_requant_offset,
	input  logic signed [15:0]          cfg_requant_scale,
	input  logic [5:0]                  cfg_requant_shift,

	
	output logic [num_array-1:0]                        out_valid,
	output logic signed [num_array-1:0][out_width-1:0]   out_data,
	output logic [cnt_width-1:0]      out_pe_index          
);

	
	logic                 act_rd_en;
	logic [act_addr_w-1:0] act_rd_addr;
	logic [data_width-1:0] act_rd_data;
	logic                 act_rd_valid;
	logic                 act_rd_retire_en;
	logic [act_addr_w:0]  act_rd_retire_cnt;
	logic [act_addr_w:0]  act_occ;
	logic                 act_full, act_empty;

	act_buffer #(.data_width(data_width), .depth(act_depth)) u_act (
		.clk(clk), .rst_n(rst_n),
		.wr_en(act_wr_en), .wr_data(act_wr_data), .wr_ready(act_wr_ready),
		.rd_en(act_rd_en), .rd_addr(act_rd_addr), .rd_data(act_rd_data), .rd_valid(act_rd_valid),
		.rd_retire_en(act_rd_retire_en), .rd_retire_cnt(act_rd_retire_cnt),
		.occupancy(act_occ), .full(act_full), .empty(act_empty)
	);

	
	logic                  wload_start   [num_array];
	logic [wgt_addr_w-1:0]  wload_base    [num_array];
	logic                  wload_busy    [num_array];
	logic                  wload_done    [num_array];
	logic                  wload_shift_en[num_array];
	logic [data_width-1:0] wload_shift_d [num_array];
	logic [data_width-1:0] wload_pe_w    [num_array][num_pe]; 

	generate
		genvar ga;
		for (ga = 0; ga < num_array; ga++) begin : g_wload
			
			weight_mem_load #(
				.weight_w(data_width), .num_pe(num_pe), .total_weight(wgt_depth)
			) u_wload (
				.clk(clk), .rst_n(rst_n),
				.cfg_wr_en(cfg_wgt_wr_en[ga]), .cfg_wr_addr(cfg_wgt_wr_addr[ga]), .cfg_wr_data(cfg_wgt_wr_data[ga]),
				.load_tile_start(wload_start[ga]), .tile_base_addr(wload_base[ga]),
				.load_tile_busy(wload_busy[ga]), .load_tile_done(wload_done[ga]),
				.pe_shift_en(wload_shift_en[ga]), .pe_shift_data(wload_shift_d[ga]),
								.pe_weight()
			);
		end
	endgenerate

		logic signed [data_width-1:0] mac_wgt_serial_in [num_array];
	logic signed [data_width-1:0] mac_wgt_serial_out[num_array];
	logic                  mac_shift_en   [num_array];
	logic                  mac_capture_en [num_array];
	logic                  mac_acc_clear  [num_array];
	logic                  mac_valid_in   [num_array];
	logic signed [data_width-1:0] mac_act_in [num_array];
	logic signed [acc_width-1:0]  mac_acc_out[num_array][num_pe];
	logic                  mac_out_load_en [num_array];
	logic                  mac_out_shift_en[num_array];
		logic signed [num_array-1:0][acc_width-1:0] mac_result_serial;

	generate
		genvar gb;
		for (gb = 0; gb < num_array; gb++) begin : g_wire_wgt
			assign mac_wgt_serial_in[gb] = wload_shift_d[gb];
			assign mac_shift_en[gb]      = wload_shift_en[gb];
		end
	endgenerate

	mac_system #(
		.data_width(data_width), .acc_width(acc_width), .num_pe(num_pe), .num_array(num_array)
	) u_mac (
		.clk(clk), .rst_n(rst_n),
		.cfg_precision(cfg_precision),
		.weight_serial_in(mac_wgt_serial_in), .weight_serial_out(mac_wgt_serial_out),
		.shift_en(mac_shift_en), .capture_en(mac_capture_en),
		.acc_clear(mac_acc_clear), .valid_in(mac_valid_in), .act_in(mac_act_in), .acc_out(mac_acc_out),
		.output_load_en(mac_out_load_en), .output_shift_en(mac_out_shift_en),
		.result_serial_out(mac_result_serial)
	);

	
	logic                          relu_en;
	
	logic signed [num_array-1:0][acc_width-1:0]   relu_in;
	logic signed [num_array-1:0][acc_width-1:0]   relu_out;
	logic                          relu_valid;

	relu #(.data_width(acc_width), .lanes(num_array)) u_relu (
		.clk(clk), .rst_n(rst_n), .en(relu_en), .cfg_bypass(cfg_relu_bypass),
		.data_in(relu_in), .data_out(relu_out), .valid_out(relu_valid)
	);

	
	logic requant_en;
	logic requant_valid_arr [num_array];

	generate
		genvar gc;
		for (gc = 0; gc < num_array; gc++) begin : g_requant
			requant #(
				.acc_width(acc_width), .scale_width(16), .shift_width(6), .out_width(out_width)
			) u_requant (
				.clk(clk), .rst_n(rst_n), .en(requant_en), .cfg_bypass(cfg_requant_bypass),
				.data_in(relu_out[gc]),
				.cfg_offset(cfg_requant_offset), .cfg_scale(cfg_requant_scale), .cfg_shift(cfg_requant_shift),
				.data_out(out_data[gc]), .valid_out(requant_valid_arr[gc])
			);
			assign out_valid[gc] = requant_valid_arr[gc];
		end
	endgenerate

		logic                   fsm_wload_start;
	logic [wgt_addr_w-1:0]  fsm_wload_base;
	logic                   fsm_mac_capture_en;
	logic                   fsm_mac_acc_clear;
	logic                   fsm_mac_valid_in;
	logic signed [data_width-1:0] fsm_act_hold;
	logic                   fsm_mac_out_load_en;
	logic                   fsm_mac_out_shift_en;
	logic [cnt_width-1:0]   red_step;
	logic [pe_cnt_w-1:0]    out_pe_cnt;

	assign out_pe_index = out_pe_cnt;

	npu_fsm #(
		.data_width(data_width), .cnt_width(cnt_width), .num_pe(num_pe),
		.act_addr_w(act_addr_w), .wgt_addr_w(wgt_addr_w), .pe_cnt_w(pe_cnt_w)
	) u_fsm (
		.clk(clk), .rst_n(rst_n),
		.start(start), .cfg_reduction_len(cfg_reduction_len),
		.wload_done0(wload_done[0]), .act_rd_valid(act_rd_valid), .act_rd_data(act_rd_data),
		.relu_valid(relu_valid), .requant_valid0(requant_valid_arr[0]),
		.busy(busy), .done(done),
		.wload_start(fsm_wload_start), .wload_base(fsm_wload_base),
		.mac_capture_en(fsm_mac_capture_en), .mac_acc_clear(fsm_mac_acc_clear),
		.mac_valid_in(fsm_mac_valid_in), .act_hold(fsm_act_hold),
		.mac_out_load_en(fsm_mac_out_load_en), .mac_out_shift_en(fsm_mac_out_shift_en),
		.act_rd_en(act_rd_en), .act_rd_addr(act_rd_addr), .act_rd_retire_en(act_rd_retire_en),
		.relu_en(relu_en), .requant_en(requant_en),
		.red_step(red_step), .out_pe_cnt(out_pe_cnt)
	);

	assign act_rd_retire_cnt = 1'b1;


	generate
		genvar gd;
		for (gd = 0; gd < num_array; gd++) begin : g_ctrl
			assign wload_start[gd]     = fsm_wload_start;
			assign wload_base[gd]      = fsm_wload_base;
			assign mac_capture_en[gd]  = fsm_mac_capture_en;
			assign mac_acc_clear[gd]   = fsm_mac_acc_clear;
			assign mac_valid_in[gd]    = fsm_mac_valid_in;
			assign mac_act_in[gd]      = fsm_act_hold; 
			assign mac_out_load_en[gd] = fsm_mac_out_load_en;
			assign mac_out_shift_en[gd]= fsm_mac_out_shift_en;
		end
	endgenerate

	generate
		genvar ge;
		for (ge = 0; ge < num_array; ge++) begin : g_relu_in
			assign relu_in[ge] = mac_result_serial[ge];
		end
	endgenerate

endmodule
