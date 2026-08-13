`timescale 1ns/1ps
// ============================================================================
// npu_apb_top.sv
//
// Wrapper noi apb_slave_regs.sv (giao dien bus, phia host) voi npu_ctrl_top
// (dieu khien + datapath, phia NPU). Day la module TREN CUNG cung (top-level
// cua toan he thong NPU) - neu ghep vao Platform Designer/Qsys tren
// DE10-Standard, day la module se duoc bao boc them boi cau Avalon-MM<->APB
// (hoac dung truc tiep neu Qsys ho tro APB component).
//
// Khong co logic dieu khien moi o day - CHI la day noi (structural), de giu
// npu_ctrl_top nguyen ven (da duoc verify) va apb_slave_regs doc lap, de test
// rieng tung khoi truoc khi ghep.
// ============================================================================

module npu_apb_top #(
	parameter int data_width  = 8,
	parameter int acc_width   = 32,
	parameter int out_width   = 8,
	parameter int num_pe      = 16,
	parameter int num_array   = 4,
	parameter int act_depth   = 1024,
	parameter int wgt_depth   = 4096,
	parameter int cnt_width   = 16,
	parameter int paddr_width = 12,

	localparam int wgt_addr_w = $clog2(wgt_depth)
)(
	input logic clk,
	input logic rst_n,

	// ---- APB4 slave (phia host) ----
	input  logic                   psel,
	input  logic                   penable,
	input  logic                   pwrite,
	input  logic [paddr_width-1:0] paddr,
	input  logic [31:0]            pwdata,
	output logic                   pready,
	output logic [31:0]            prdata,
	output logic                   pslverr
);

	// ---- day noi apb_slave_regs <-> npu_ctrl_top ----
	logic                  start, busy, done;
	logic [cnt_width-1:0]  cfg_reduction_len;
	logic                  cfg_precision;

	logic                  act_wr_en;
	logic [data_width-1:0] act_wr_data;
	logic                  act_wr_ready;

	logic                  cfg_wgt_wr_en   [num_array];
	logic [wgt_addr_w-1:0] cfg_wgt_wr_addr [num_array];
	logic [data_width-1:0] cfg_wgt_wr_data [num_array];

	logic                        cfg_relu_bypass, cfg_requant_bypass;
	logic signed [acc_width-1:0] cfg_requant_offset;
	logic signed [15:0]          cfg_requant_scale;
	logic [5:0]                  cfg_requant_shift;

	logic                        out_valid [num_array];
	logic signed [out_width-1:0] out_data  [num_array];
	logic [cnt_width-1:0]        out_pe_index;

	apb_slave_regs #(
		.data_width(data_width), .acc_width(acc_width), .out_width(out_width),
		.num_pe(num_pe), .num_array(num_array), .cnt_width(cnt_width),
		.wgt_addr_w(wgt_addr_w), .paddr_width(paddr_width)
	) u_apb (
		.clk(clk), .rst_n(rst_n),
		.psel(psel), .penable(penable), .pwrite(pwrite),
		.paddr(paddr), .pwdata(pwdata),
		.pready(pready), .prdata(prdata), .pslverr(pslverr),

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
