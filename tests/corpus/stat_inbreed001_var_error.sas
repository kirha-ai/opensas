/* expect-rc: 1
   STAT-INBREED-001 negative: the VAR statement names three or four
   variables (p.5278); two is a user error and prints nothing.
   Data: invented. */
options nocenter;
title;
data ped;
input animal $ sire $ dam $;
datalines;
A . .
B A .
;
proc inbreed data=ped matrix;
var animal sire;
run;
