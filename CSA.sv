`timescale 1ns/1ps

module fa (
input logic a, b, cin,
output logic sum, cout
);
logic w1, w2, w3;

xor uxor1 (w1, a, b);
xor uxor2 (sum, w1, cin);
and uand1 (w2, a, b);
and uand2 (w3, cin, w1);
or uor1 (cout, w2, w3);
endmodule 

module CSA3to2 #(
parameter int W = 8)(
input logic [W-1:0] ina,
input logic [W-1:0] inb,
input logic [W-1:0] incin,
output logic [W-1:0] sumout,
output logic [W-1:0] coutt
);
logic [W-1:0] carry;
genvar i;
generate 
for (i = 0; i < W; i = i+1) begin : fa_array
fa fa_inst (
.a(ina[i]),
.b(inb[i]),
.cin(incin[i]),
.sum(sumout[i]),
.cout(carry[i])
);
end
endgenerate
assign coutt = carry << 1;
endmodule
