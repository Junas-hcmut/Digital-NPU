`timescale 1ns/1ps

module CSA8to2 #(
parameter int W = 16 
)(
input logic [W-1:0] pp0, pp1, pp2, pp3, pp4 , pp5, pp6, pp7,
input logic [W-1:0] bw_const,
output logic [W-1:0] sum_out,
output logic [W-1:0] c_out
);
//8 to 6
logic [W-1:0] s1, c1, s2, c2;
CSA3to2 #(.W(W)) u_l1_0 (.ina(pp0), .inb(pp1), .incin(pp2), .sumout(s1), .coutt(c1));
CSA3to2 #(.W(W)) u_l1_1 (.ina(pp3), .inb(pp4), .incin(pp5), .sumout(s2), .coutt(c2));

logic [W-1:0] s3, c3, s4, c4;
CSA3to2 #(.W(W)) u_l2_0 (.ina(s1), .inb(c1), .incin(s2), .sumout(s3), .coutt(c3));
CSA3to2 #(.W(W)) u_l2_1 (.ina(c2), .inb(pp6), .incin(pp7), .sumout(s4), .coutt(c4));

logic [W-1:0] s5, c5;
CSA3to2 #(.W(W)) u_l3_0 (.ina(s3), .inb(c3), .incin(s4), .sumout(s5), .coutt(c5));

logic [W-1:0] s6, c6;
CSA3to2 #(.W(W)) u_l4_0 (.ina(s5), .inb(c5), .incin(c4), .sumout(s6), .coutt(c6);

CSA3to2 #(.W(W)) u_l5_0 (.ina(s6), .inb(c6), .incin(bw_const), .sumout(sum_out), .coutt(c_out));

endmodule 

