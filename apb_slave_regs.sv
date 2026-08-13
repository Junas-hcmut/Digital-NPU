`timescale 1ns/1ps

//   - Transaction gom 2 chu ky: SETUP (PSEL=1,PENABLE=0) roi ACCESS
//     (PSEL=1,PENABLE=1). Slave nay tra loi ZERO-WAIT-STATE (PREADY=1'b1
//     luon luon) nen ACCESS luon dung dung 1 chu ky - don gian hoa toi da.
//   - PWRITE=1: ghi (PWDATA hop le trong ACCESS). PWRITE=0: doc (PRDATA hop
//     le trong ACCESS).
//
// BANG DIA CHI THANH GHI (word-aligned, byte offset):
//   0x00 CTRL       [0]=start (W, tu xoa - la 1 xung 1 chu ky, doc luon ra 0)
//                   [1]=cfg_precision (RW, 0=INT8,1=INT4)
//   0x04 STATUS     [0]=busy (RO)
//                   [1]=done (RO, sticky - set khi FSM bao done, tu xoa khi
//                       doc thanh ghi nay HOAC khi ghi start moi)
//   0x08 RED_LEN    cfg_reduction_len (RW, cnt_width bit thap)
//   0x0C BYPASS     [0]=relu_bypass, [1]=requant_bypass (RW)
//   0x10 RQ_OFFSET  cfg_requant_offset (RW, acc_width bit - GIA DINH
//                       acc_width <= 32, vua 1 thanh ghi)
//   0x14 RQ_SCALE   cfg_requant_scale (RW, 16 bit thap)
//   0x18 RQ_SHIFT   cfg_requant_shift (RW, 6 bit thap)
//   0x1C ACT_PUSH   W: day 1 mau vao act_buffer (data_width bit thap ->
//                       act_wr_data, pulse act_wr_en 1 chu ky)
//                   R: bit0 = act_wr_ready (con cho nhan mau moi khong)
//   0x20 WGT_SEL    chon array dich (RW, array_sel_w bit thap, 0..num_array-1)
//   0x24 WGT_ADDR   dia chi trong weight_mem cua array da chon (RW)
//   0x28 WGT_DATA   W: ghi 1 gia tri trong so vao (WGT_SEL,WGT_ADDR), pulse
//                       cfg_wgt_wr_en[WGT_SEL] 1 chu ky
//                   R: doc lai gia tri vua ghi gan nhat (khong doc tu memory
//                       that trong weight_mem_loader)
//   0x40 .. RESULT  RO - ket qua sau requant, da duoc tu dong CHOT VAO day
//                       moi khi out_valid[i] len trong luc chay (KHONG can
//                       host doc kip real-time luc dang chay). Chi so:
//                       idx = out_pe_index*num_array + array_idx
//                       byte_addr = 0x40 + idx*4
//                       num_pe*num_array gia tri sau khi FSM chay xong.
module apb_slave_regs #(
	parameter int data_width   = 8,
	parameter int acc_width    = 32,
	parameter int out_width    = 8,
	parameter int num_pe       = 16,
	parameter int num_array    = 4,
	parameter int cnt_width    = 16,
	parameter int wgt_addr_w   = 12,
	parameter int paddr_width  = 12,

	localparam int array_sel_w = (num_array > 1) ? $clog2(num_array) : 1
)(
	input logic clk,
	input logic rst_n,
	//  APB4 slave 
	input  logic                    psel,
	input  logic                    penable,
	input  logic                    pwrite,
	input  logic [paddr_width-1:0]  paddr,
	input  logic [31:0]             pwdata,
	output logic                    pready,
	output logic [31:0]             prdata,
	output logic                    pslverr,

	//  noi sang npu_ctrl_top 
	output logic                  start,
	input  logic                  busy,
	input  logic                  done,
	output logic [cnt_width-1:0]  cfg_reduction_len,
	output logic                  cfg_precision,

	output logic                  act_wr_en,
	output logic [data_width-1:0] act_wr_data,
	input  logic                  act_wr_ready,

	output logic                   cfg_wgt_wr_en   [num_array],
	output logic [wgt_addr_w-1:0]  cfg_wgt_wr_addr [num_array],
	output logic [data_width-1:0]  cfg_wgt_wr_data [num_array],

	output logic                        cfg_relu_bypass,
	output logic                        cfg_requant_bypass,
	output logic signed [acc_width-1:0] cfg_requant_offset,
	output logic signed [15:0]          cfg_requant_scale,
	output logic [5:0]                  cfg_requant_shift,

	input logic                      out_valid [num_array],
	input logic signed [out_width-1:0] out_data [num_array],
	input logic [cnt_width-1:0]      out_pe_index
);

	//  dia chi thanh ghi (word index = byte_addr >> 2) 
	localparam int A_CTRL      = 0;
	localparam int A_STATUS    = 1;
	localparam int A_RED_LEN   = 2;
	localparam int A_BYPASS    = 3;
	localparam int A_RQ_OFFSET = 4;
	localparam int A_RQ_SCALE  = 5;
	localparam int A_RQ_SHIFT  = 6;
	localparam int A_ACT_PUSH  = 7;
	localparam int A_WGT_SEL   = 8;
	localparam int A_WGT_ADDR  = 9;
	localparam int A_WGT_DATA  = 10;
	localparam int A_RESULT_BASE = 16; // byte 0x40

	logic [paddr_width-3:0] word_idx;
	assign word_idx = paddr[paddr_width-1:2];

	logic apb_write, apb_read;
	assign apb_write = psel && penable && pwrite;
	assign apb_read  = psel && penable && !pwrite;

	// Slave khong wait-state
	assign pready  = 1'b1;
	assign pslverr = 1'b0;

	//  thanh ghi cau hinh 
	logic                  precision_r;
	logic [cnt_width-1:0]  red_len_r;
	logic                  relu_bypass_r, requant_bypass_r;
	logic signed [acc_width-1:0] rq_offset_r;
	logic signed [15:0]          rq_scale_r;
	logic [5:0]                  rq_shift_r;
	logic [array_sel_w-1:0]      wgt_sel_r;
	logic [wgt_addr_w-1:0]       wgt_addr_r;
	logic [data_width-1:0]       wgt_data_last_r;
	logic                        done_sticky_r;

	assign cfg_precision      = precision_r;
	assign cfg_reduction_len  = red_len_r;
	assign cfg_relu_bypass    = relu_bypass_r;
	assign cfg_requant_bypass = requant_bypass_r;
	assign cfg_requant_offset = rq_offset_r;
	assign cfg_requant_scale  = rq_scale_r;
	assign cfg_requant_shift  = rq_shift_r;

	// start: xung to hop dung 1 chu ky APB ACCESS khi ghi CTRL.bit0=1
	assign start = apb_write && (word_idx == A_CTRL) && pwdata[0];

	// act_wr_en / act_wr_data: xung to hop khi ghi ACT_PUSH
	assign act_wr_en   = apb_write && (word_idx == A_ACT_PUSH);
	assign act_wr_data = pwdata[data_width-1:0];

	// cfg_wgt_wr_en[i] / addr / data: xung to hop khi ghi WGT_DATA, chi
	// dung 1 array duoc chon boi wgt_sel_r
	generate
		genvar gi;
		for (gi = 0; gi < num_array; gi++) begin : g_wgt_wr
			assign cfg_wgt_wr_en[gi]   = apb_write && (word_idx == A_WGT_DATA) && (wgt_sel_r == gi);
			assign cfg_wgt_wr_addr[gi] = wgt_addr_r;
			assign cfg_wgt_wr_data[gi] = pwdata[data_width-1:0];
		end
	endgenerate

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			precision_r      <= 1'b0;
			red_len_r        <= '0;
			relu_bypass_r    <= 1'b0;
			requant_bypass_r <= 1'b0;
			rq_offset_r      <= '0;
			rq_scale_r       <= 16'sd1; // mac dinh scale=1 (khong doi gia tri) - an toan hon 0
			rq_shift_r       <= '0;
			wgt_sel_r        <= '0;
			wgt_addr_r       <= '0;
			wgt_data_last_r  <= '0;
			done_sticky_r    <= 1'b0;
		end else begin
			if (apb_write) begin
				unique case (word_idx)
					A_CTRL:      precision_r      <= pwdata[1];
					A_RED_LEN:   red_len_r        <= pwdata[cnt_width-1:0];
					A_BYPASS:    begin
						relu_bypass_r    <= pwdata[0];
						requant_bypass_r <= pwdata[1];
					end
					A_RQ_OFFSET: rq_offset_r <= pwdata[acc_width-1:0];
					A_RQ_SCALE:  rq_scale_r  <= pwdata[15:0];
					A_RQ_SHIFT:  rq_shift_r  <= pwdata[5:0];
					A_WGT_SEL:   wgt_sel_r   <= pwdata[array_sel_w-1:0];
					A_WGT_ADDR:  wgt_addr_r  <= pwdata[wgt_addr_w-1:0];
					A_WGT_DATA:  wgt_data_last_r <= pwdata[data_width-1:0];
					default: ;
				endcase
			end

			// done sticky: set khi FSM bao done; xoa khi bat dau lan chay
			// moi (start) hoac khi host da doc STATUS (read-to-clear)
			if (start)
				done_sticky_r <= 1'b0;
			else if (done)
				done_sticky_r <= 1'b1;
			else if (apb_read && (word_idx == A_STATUS))
				done_sticky_r <= 1'b0;
		end
	end

	// ---- bo nho ket qua: tu dong chot moi khi out_valid[i] len ----
	logic signed [out_width-1:0] result_mem [num_pe*num_array];

	generate
		genvar gj;
		for (gj = 0; gj < num_array; gj++) begin : g_result_capture
			always_ff @(posedge clk or negedge rst_n) begin
				if (!rst_n) begin
					// khong can reset tung phan tu result_mem (chi la vung
					// nho ket qua, khong anh huong logic dieu khien)
				end else if (out_valid[gj]) begin
					result_mem[out_pe_index*num_array + gj] <= out_data[gj];
				end
			end
		end
	endgenerate

	// ---- doc thanh ghi ----
	always_comb begin
		prdata = 32'h0;
		if (apb_read || (psel && !pwrite)) begin
			if (word_idx >= A_RESULT_BASE && word_idx < A_RESULT_BASE + num_pe*num_array) begin
				// sign-extend ket qua out_width-bit ra 32 bit
				prdata = {{(32-out_width){result_mem[word_idx - A_RESULT_BASE][out_width-1]}},
				           result_mem[word_idx - A_RESULT_BASE]};
			end else begin
				unique case (word_idx)
					A_CTRL:      prdata = {30'b0, precision_r, 1'b0}; // start doc luon ra 0
					A_STATUS:    prdata = {30'b0, done_sticky_r, busy};
					A_RED_LEN:   prdata = {{(32-cnt_width){1'b0}}, red_len_r};
					A_BYPASS:    prdata = {30'b0, requant_bypass_r, relu_bypass_r};
					A_RQ_OFFSET: prdata = {{(32-acc_width){rq_offset_r[acc_width-1]}}, rq_offset_r};
					A_RQ_SCALE:  prdata = {{16{rq_scale_r[15]}}, rq_scale_r};
					A_RQ_SHIFT:  prdata = {26'b0, rq_shift_r};
					A_ACT_PUSH:  prdata = {31'b0, act_wr_ready};
					A_WGT_SEL:   prdata = {{(32-array_sel_w){1'b0}}, wgt_sel_r};
					A_WGT_ADDR:  prdata = {{(32-wgt_addr_w){1'b0}}, wgt_addr_r};
					A_WGT_DATA:  prdata = {{(32-data_width){1'b0}}, wgt_data_last_r};
					default:     prdata = 32'h0;
				endcase
			end
		end
	end

endmodule
