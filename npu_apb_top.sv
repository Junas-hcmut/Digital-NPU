`timescale 1ns/1ps


module npu_apb_top #(
	parameter int data_width  = 8,
	parameter int acc_width   = 32,
	parameter int out_width   = 8,
	parameter int num_pe      = 16,
	parameter int num_array   = 4,
	parameter int act_depth   = 1024,
	parameter int wgt_depth   = 4096,
	parameter int cnt_width   = 16,
	parameter int paddr_width = 12
)(
	input logic clk,
	input logic rst_n,


	input  logic                   PSEL,
	input  logic                   PENABLE,
	input  logic                   PWRITE,
	input  logic [paddr_width-1:0] PADDR,
	input  logic [31:0]            PWDATA,
	output logic                   PREADY,
	output logic [31:0]            PRDATA,
	output logic                   PSLVERR
);

		localparam int wgt_addr_w = $clog2(wgt_depth);

	logic                  start, busy, done;
	logic [cnt_width-1:0]  cfg_reduction_len;
	logic                  cfg_precision;

	logic                  act_wr_en;
	logic [data_width-1:0] act_wr_data;
	logic                  act_wr_ready;

		logic [num_array-1:0]                    cfg_wgt_wr_en;
	logic [num_array-1:0][wgt_addr_w-1:0]    cfg_wgt_wr_addr;
	logic [num_array-1:0][data_width-1:0]    cfg_wgt_wr_data;

	logic                        cfg_relu_bypass, cfg_requant_bypass;
	logic signed [acc_width-1:0] cfg_requant_offset;
	logic signed [15:0]          cfg_requant_scale;
	logic [5:0]                  cfg_requant_shift;

	logic [num_array-1:0]                        out_valid;
	logic signed [num_array-1:0][out_width-1:0]  out_data;
	logic [cnt_width-1:0]        out_pe_index;

	apb_slave_regs #(
		.data_width(data_width), .acc_width(acc_width), .out_width(out_width),
		.num_pe(num_pe), .num_array(num_array), .cnt_width(cnt_width),
		.wgt_addr_w(wgt_addr_w), .paddr_width(paddr_width)
	) u_apb (
		.clk(clk), .rst_n(rst_n),
				.psel(PSEL), .penable(PENABLE), .pwrite(PWRITE),
		.paddr(PADDR), .pwdata(PWDATA),
		.pready(PREADY), .prdata(PRDATA), .pslverr(PSLVERR),

		.start(start), .busy(busy), .done(done),
		.cfg_reduction_len(cfg_reduction_len), .cfg_precision(cfg_precision),
		.act_wr_en(act_wr_en), .act_wr_data(act_wr_data), .act_wr_ready(act_wr_ready),
		.cfg_wgt_wr_en(cfg_wgt_wr_en), .cfg_wgt_wr_addr(cfg_wgt_wr_addr), .cfg_wgt_wr_data(cfg_wgt_wr_data),
		.cfg_relu_bypass(cfg_relu_bypass), .cfg_requant_bypass(cfg_requant_bypass),
		.cfg_requant_offset(cfg_requant_offset), .cfg_requant_scale(cfg_requant_scale), .cfg_requant_shift(cfg_requant_shift),
		.out_valid(out_valid), .out_data(out_data), .out_pe_index(out_pe_index)
	);

	npu_ctrl_top #(
		.data_width(data_width), .acc_width(acc_width), .out_width(out_width),
		.num_pe(num_pe), .num_array(num_array), .act_depth(act_depth),
		.wgt_depth(wgt_depth), .cnt_width(cnt_width)
	) u_npu (
		.clk(clk), .rst_n(rst_n),

		.start(start), .busy(busy), .done(done),
		.cfg_reduction_len(cfg_reduction_len), .cfg_precision(cfg_precision),

		.act_wr_en(act_wr_en), .act_wr_data(act_wr_data), .act_wr_ready(act_wr_ready),

		.cfg_wgt_wr_en(cfg_wgt_wr_en), .cfg_wgt_wr_addr(cfg_wgt_wr_addr), .cfg_wgt_wr_data(cfg_wgt_wr_data),

		.cfg_relu_bypass(cfg_relu_bypass), .cfg_requant_bypass(cfg_requant_bypass),
		.cfg_requant_offset(cfg_requant_offset), .cfg_requant_scale(cfg_requant_scale), .cfg_requant_shift(cfg_requant_shift),

		.out_valid(out_valid), .out_data(out_data), .out_pe_index(out_pe_index)
	);

endmodule
