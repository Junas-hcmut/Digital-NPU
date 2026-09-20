`timescale 1ns/1ps
module RCA #(
parameter int W = 16
)(
input logic [W-1:0] aa,
input logic [W-1:0] bb,

output logic [W-1:0] ssum,
output logic ccout
);

logic [W:0] ccarry;
assign ccarry[0] = 1'b0;

genvar i;
generate
for (i=0; i < W; i = i +1) begin : gen_fa
fa fa_inst(
.a(aa[i]),
.b(bb[i]),
.cin(ccarry[i]),
.sum(ssum[i]),
.cout(ccarry[i+1])
);
end 
endgenerate

assign ccout = ccarry[W];
endmodule

