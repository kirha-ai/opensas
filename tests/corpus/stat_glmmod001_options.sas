/* STAT-GLMMOD-001: PROC GLMMOD statement options and FREQ/WEIGHT edge values
 * (invented data). WEIGHT 0, negative or missing and FREQ negative, 0 or
 * fractional below 1 keep the design point but are not "Used"; FREQ is
 * listed and stored truncated (1.7 -> 1, 2.5 -> 2). NAMELEN=25, PREFIX=,
 * ZEROBASED, OUTPARM=, ORDER=FREQ with the default DATA= (last data set), and a CLASS variable that is also the
 * BY variable (one level per group). Tokens match a SAS 9.4 run.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'R';
data a;
input g $ y f w;
datalines;
A 1 1 0
A 2 1 -2
A 3 1 .
A 4 -1 1
A 5 0 1
A 6 1.7 1
B 7 2.5 1
B 8 0.5 1
B 9 1 1
B 10 1 2
;
proc glmmod data=a outdesign=d;
class g;
freq f;
weight w;
model y = g;
run;
proc print data=d; run;
proc glmmod data=a namelen=25 prefix=X zerobased outparm=p; class g; model y=g; run;
proc print data=p; run;
data last; set a; run;
proc glmmod order=freq; class g; model y=g; run;
proc glmmod data=a; by g; class g; model y=g; run;
