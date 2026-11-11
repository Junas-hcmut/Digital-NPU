`timescale 1ns/1ps


module fa (
	input  logic a, b, cin,
	output logic sum, cout
);

	logic w1, w2, w3;

	xor uxor1 (w1,   a,  b);
	xor uxor2 (sum,  w1, cin);
	and uand1 (w2,   a,  b);
	and uand2 (w3,   cin, w1);
	or  uor1  (cout, w2, w3);

endmodule
