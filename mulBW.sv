`timescale 1ns/1ps
module mulBW (
input logic signed [7:0] a, 
input logic signed [7:0] b,
output logic signed [15:0] p
);
logic [15:0] pp [8];
genvar i;
generate 
for (i=0; i<7; i++) begin : gen_pp_0_to_6
assign pp[i] = { 8'b0, ~(a[7] & b[i]), (a[6:0] & {7{b[i]}}) } << i;
end
endgenerate 
assign pp [7] = {8'b0 , a[7] & b[7], ~(a[6:0] & {7{b[7]}}) } << 7;
localparam logic [15:0] BW_CONSTANT = (16'h1 << 8)|(16'h1 << 15);

logic [15:0] csa_sum, csa_carry;
CSA8to2 #(.W(16)) u_csa8to2 (
	.pp0(pp[0]), 
	.pp1(pp[1]), 
	.pp2(pp[2]), 
	.pp3(pp[3]), 
	.pp4(pp[4]), 
	.pp5(pp[5]), 
	.pp6(pp[6]), 
	.pp7(pp[7]), 
	.bw_const(BW_CONSTANT), 
	.sum_out(csa_sum), 
	.c_out(csa_carry)
	);

logic [15:0] final_s;
logic final_c;
RCA #(.W(16)) u_rca (.aa(csa_sum), .bb(csa_carry), .ssum(final_s), .ccout(final_c));

assign p = final_s;
endmodule
