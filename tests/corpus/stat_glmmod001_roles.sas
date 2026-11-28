/* STAT-GLMMOD-001: FREQ, WEIGHT, missing values, NOINT and BY (invented data).
 * Observations with a missing response, CLASS or covariate value leave the
 * design; a missing/zero FREQ or missing/negative WEIGHT keeps the design
 * point but is not "Used". FREQ/WEIGHT and BY variables are copied to
 * OUTDESIGN=/OUTPARM=, BY variables first. Design points renumber from 1
 * in each BY group. Tokens match a SAS 9.4 run of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Q';
data a;
input g $ h x y f w;
datalines;
A 1 1 4 1 2
A 2 2 6 2 1
A 1 3 . 1 1
B 2 4 9 . 1
B 1 5 13 3 .
B 2 6 12 0 1
A . 7 17 1 1
B 1 8 19 1 -1
;
proc glmmod data=a outdesign=d1 outparm=p1;
class g h;
freq f;
weight w;
model y = g h g*h x;
run;
proc print data=d1; run;
proc print data=p1; run;
proc glmmod data=a outdesign=d2;
class g;
model y = g / noint;
run;
proc print data=d2; run;
data b; set a; if y ne .; run;
proc sort data=b; by g; run;
proc glmmod data=b outdesign=d3 outparm=p3;
by g;
class h;
model y = h;
run;
proc print data=d3; run;
proc print data=p3; run;
