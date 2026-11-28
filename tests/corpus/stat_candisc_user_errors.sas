/* expect-rc: 1
 * STAT-CANDISC-001: user errors (rc 1, no listing): no CLASS statement ("A
 * CLASS statement is required", p.2159), two CLASS variables, a character
 * VAR variable, an unknown FREQ variable. An empty input data set only
 * writes a NOTE. Messages as SAS 9.4 writes them. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title 'Invented Plants';
data nums; input g y1 y2 @@; datalines;
1 1 2 1 2 3 1 3 3 1 2 1 2 5 4 2 6 6 2 5 5 2 7 4 3 9 1 3 8 2 3 9 3 3 10 2
;
data plants;
  input grp $ x1 x2 x3 f w;
  if grp = "." then grp = " ";
  datalines;
A 2.1 3.5 1.0 1 1.0
A 2.5 3.1 1.4 2 0.5
A 1.9 3.9 0.8 1 1.5
A 2.8 3.3 1.9 1 1.0
A 2.2 . 1.1 1 1.0
B 3.9 2.2 2.5 1 2.0
B 4.4 2.0 2.9 3 1.0
B 3.6 2.9 2.1 1 1.0
B 4.1 2.4 3.3 1 0.5
C 5.2 4.1 1.2 2 1.0
C 5.9 4.6 0.7 1 1.0
C 6.3 3.8 1.6 1 1.5
C 5.5 4.9 1.1 1 1.0
. 4.0 3.0 2.0 1 1.0
;
proc candisc data=nums; var y1 y2; run;
proc candisc data=nums; class g y1; var y2; run;
proc candisc data=plants; class grp; var grp x1; run;
proc candisc data=nums; class g; var y1 y2; freq nosuch; run;
proc candisc data=nums(obs=0); class g; var y1 y2; run;
