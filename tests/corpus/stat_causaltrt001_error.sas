/* expect-rc: 1
 * STAT-CAUSALTRT-001: user errors are rc 1 with no output: the PSMODEL
 * statement is required (p.2424). Invented data.
 */
options nodate nonumber nocenter;
title; footnote;
data s;
input t y x;
datalines;
1 1 1
0 0 2
1 0 3
0 1 4
;
run;
proc causaltrt data=s; model y; run;
