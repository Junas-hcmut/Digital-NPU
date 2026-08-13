`timescale 1ns/1ps
// ============================================================================
// npu_ctrl_top.sv (v2 - viet lai theo dung kien truc mac_system that cua ban)
//
// Khac voi ban v1 truoc (gia dinh sai: act_in la 1 "cua so" NUM_PE gia tri
// nap 1 lan roi tinh 1 phat), ban nay dung dung cach mac_chain hoat dong:
//   - act_in LA 1 GIA TRI SCALAR, broadcast cho ca num_pe PE trong 1 array,
//     MOI ARRAY co the nhan cung 1 gia tri act_in (cung 1 chieu reduction).
//   - Voi MOI buoc reduction t (t=0..reduction_len-1):
//       1. Shift num_pe trong so MOI (cho buoc t) vao tung array qua
//          weight_serial_in/shift_en (dung song song weight_mem_loader
//          rieng cho tung array - vi moi array giu 1 nhom output-channel
//          khac nhau, can trong so khac nhau).
//       2. capture_en 1 xung -> chot trong so vao active weight_reg cua
//          tat ca PE trong array do.
//       3. Doc 1 gia tri activation tu act_buffer, dua vao act_in (broadcast
//          cho MOI array), valid_in=1 1 xung -> moi PE tich luy act*weight
//          vao chinh acc_reg cua no (KHONG can cong don "tile" nhu ban v1,
//          vi accumulator trong mac_unit da tu cong don qua tung chu ky).
//   - Sau khi het reduction_len buoc: output_load_en chot toan bo acc_out
//     cua moi array vao thanh ghi dich, roi output_shift_en lien tuc num_pe
//     lan de doc tuan tu tung gia tri result_serial_out (moi array 1 gia
//     tri/chu ky, song song num_array array) -> qua relu (lanes=num_array)
//     -> qua requant (1 instance rieng cho moi array) -> xuat ra ngoai.
//
// ******************************************************************
// CANH BAO VE TIMING CAN TU KIEM TRA LAI BANG SIMULATOR THAT:
//   O trang thai S_OUT_SHIFT, minh doc result_serial_out VA pulse
//   output_shift_en TRONG CUNG 1 chu ky (doc gia tri hien tai, dong thoi
//   yeu cau dich sang gia tri ke tiep cho vong sau). Cach nay dung VE MAT
//   LOGIC (da kiem tra bang mo hinh dieu khien Python), nhung minh KHONG co
//   simulator SystemVerilog that (iverilog/Verilator/Questa) trong moi
//   truong nay de chay dung waveform xac nhan do tre 1 chu ky cua
//   out_shift_reg trong mac_chain khop chinh xac voi gia dinh nay. Ban NEN
//   tu mo phong lai doan nay truoc khi tin tuong hoan toan.
// ============================================================================

module npu_ctrl_top #(
	parameter int data_width  = 8,
	parameter int acc_width   = 32,
	parameter int out_width   = 8,
	parameter int num_pe      = 16,
	parameter int num_array   = 4,
	parameter int act_depth   = 1024,
	parameter int wgt_depth   = 4096,   // dung luong weight_mem CUA MOI array
	parameter int cnt_width   = 16,

	localparam int act_addr_w = $clog2(act_depth),
	localparam int wgt_addr_w = $clog2(wgt_depth),
	localparam int pe_cnt_w   = $clog2(num_pe+1)
)(
	input logic clk,
	input logic rst_n,

	// ---- Dieu khien tong the ----
	input  logic              start,
	output logic              busy,
	output logic              done,
	input  logic [cnt_width-1:0] cfg_reduction_len, // so buoc reduction (chieu dai vector nhan-cong)
	input  logic              cfg_precision,     // 0=INT8, 1=INT4 (runtime) - noi thang xuong mac_system

	// ---- Nap du lieu tho vao act_buffer ----
	input  logic                  act_wr_en,
	input  logic [data_width-1:0] act_wr_data,
	output logic                  act_wr_ready,

	// ---- Nap trong so cho TUNG array (1 lan luc cau hinh model) ----
	input  logic                    cfg_wgt_wr_en    [num_array],
	input  logic [wgt_addr_w-1:0]   cfg_wgt_wr_addr  [num_array],
	input  logic [data_width-1:0]   cfg_wgt_wr_data  [num_array],

	// ---- Cau hinh ReLU / requant (dung chung cho ca lop) ----
	input  logic                     cfg_relu_bypass,
	input  logic                     cfg_requant_bypass,
	input  logic signed [acc_width-1:0] cfg_requant_offset,
	input  logic signed [15:0]          cfg_requant_scale,
	input  logic [5:0]                  cfg_requant_shift,

	// ---- Ket qua cuoi: moi chu ky xuat toi da num_array gia tri song song ----
	output logic                      out_valid   [num_array],
	output logic signed [out_width-1:0] out_data  [num_array],
	output logic [cnt_width-1:0]      out_pe_index          // pe_cnt hien tai (0..num_pe-1); kenh output that = a*num_pe? tuy quy uoc cua ban
);

	// ------------------------------------------------------------------
	// act_buffer
	// ------------------------------------------------------------------
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

	// ------------------------------------------------------------------
	// weight_mem_loader rieng cho TUNG array + tin hieu noi sang mac_system
	// ------------------------------------------------------------------
	logic                  wload_start   [num_array];
	logic [wgt_addr_w-1:0]  wload_base    [num_array];
	logic                  wload_busy    [num_array];
	logic                  wload_done    [num_array];
	logic                  wload_shift_en[num_array];
	logic [data_width-1:0] wload_shift_d [num_array];
	logic [data_width-1:0] wload_pe_w    [num_array][num_pe]; // KHONG dung toi (xem ghi chu duoi)

	generate
		genvar ga;
		for (ga = 0; ga < num_array; ga++) begin : g_wload
			weight_mem_loader #(
				.weight(data_width), .num_pe(num_pe), .total_weight(wgt_depth)
			) u_wload (
				.clk(clk), .rst_n(rst_n),
				.cfg_wr_en(cfg_wgt_wr_en[ga]), .cfg_wr_addr(cfg_wgt_wr_addr[ga]), .cfg_wr_data(cfg_wgt_wr_data[ga]),
				.load_tile_start(wload_start[ga]), .tile_base_addr(wload_base[ga]),
				.load_tile_busy(wload_busy[ga]), .load_tile_done(wload_done[ga]),
				.pe_shift_en(wload_shift_en[ga]), .pe_shift_data(wload_shift_d[ga]),
				.pe_weight(wload_pe_w[ga])
				// GHI CHU: pe_weight[]/chain[] noi bo cua weight_mem_loader KHONG
				// duoc dung o day - mac_chain co chain_link RIENG cua no de
				// shift+capture that su. Minh chi lay dung luong pe_shift_en/
				// pe_shift_data (dong serial) noi thang vao shift_en/weight_
				// serial_in cua mac_system. Phan pe_weight[] o day la phan
				// cung du thua, co the cat bo sau de tiet kiem dien tich.
			);
		end
	endgenerate

	// ------------------------------------------------------------------
	// mac_system that (fixed) - instantiate truc tiep, khong con la stub
	// ------------------------------------------------------------------
	// FIX (phat hien qua kiem tra elaboration bang slang): mac_system khai
	// bao weight_serial_in/out la "signed", 2 duong day noi o day truoc do
	// lai la unsigned -> loi that su khi elaborate (khong tu chuyen doi
	// ngam giua mang packed signed/unsigned). Them "signed" cho khop.
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
	logic signed [acc_width-1:0] mac_result_serial [num_array];

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

	// ------------------------------------------------------------------
	// ReLU: xu ly num_array gia tri song song moi chu ky (1 lane/array)
	// ------------------------------------------------------------------
	logic                          relu_en;
	logic signed [acc_width-1:0]   relu_in  [num_array];
	logic signed [acc_width-1:0]   relu_out [num_array];
	logic                          relu_valid;

	relu #(.data_width(acc_width), .lanes(num_array)) u_relu (
		.clk(clk), .rst_n(rst_n), .en(relu_en), .cfg_bypass(cfg_relu_bypass),
		.data_in(relu_in), .data_out(relu_out), .valid_out(relu_valid)
	);

	// ------------------------------------------------------------------
	// Requant: 1 instance/array (moi instance xu ly dung 1 stream scalar)
	// ------------------------------------------------------------------
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

	// ------------------------------------------------------------------
	// FSM chinh - da tach rieng ra npu_fsm.sv (logic ben trong GIU NGUYEN,
	// chi doi cach to chuc thanh 1 module rieng). O day chi con phan
	// "broadcast" tin hieu scalar tu FSM ra thanh mang [num_array] cho
	// mac_system/weight_mem_loader, va noi cac tin hieu trang thai vao.
	// ------------------------------------------------------------------
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

	// ---- Broadcast tin hieu scalar tu FSM ra num_array duong day that ----
	generate
		genvar gd;
		for (gd = 0; gd < num_array; gd++) begin : g_ctrl
			assign wload_start[gd]     = fsm_wload_start;
			assign wload_base[gd]      = fsm_wload_base;
			assign mac_capture_en[gd]  = fsm_mac_capture_en;
			assign mac_acc_clear[gd]   = fsm_mac_acc_clear;
			assign mac_valid_in[gd]    = fsm_mac_valid_in;
			assign mac_act_in[gd]      = fsm_act_hold; // broadcast cung 1 gia tri cho moi array
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
