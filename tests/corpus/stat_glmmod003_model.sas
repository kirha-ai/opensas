/* expect-rc: 0
 * STAT-GLMMOD-003: CLASS / TRUNCATE, multiple dependents (one pass;
 * one pass per missing-value pattern with _YPASS_ outputs), last MODEL wins,
 * intercept-only and NOINT-without-effects designs, a CLASS response,
 * nested, continuous-nesting and @2 bar effects (S154 pp.4238-4240, GLM pp.4095-4097).
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) run of these steps (same data and statements),
 * 2026-11-28, compared token by token (whitespace-normalised). Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data t;
length g $24;
input g $ h x y1 y2 y3;
datalines;
aaaaaaaaaaaaaaaaaaaaX 1 1.5 4 5 6
aaaaaaaaaaaaaaaaaaaaY 2 2.5 5 . 7
bb 1 3 6 7 .
bb 2 4 7 8 9
aaaaaaaaaaaaaaaaaaaaX 2 5 8 9 10
bb 1 6 9 . 11
;
title 'Q1 multi dep same pattern';
proc glmmod data=t outdesign=d1 outparm=p1; class h; model y1 x = h; run;
proc print data=d1; run; proc print data=p1; run;
title 'Q2 multi dep different patterns';
proc glmmod data=t outdesign=d2 outparm=p2; class h; model y1 y2 y3 = h; run;
proc print data=d2; run; proc print data=p2; run;
title 'Q3 truncate';
proc glmmod data=t; class g / truncate; model y1 = g; run;
title 'Q4 no truncate';
proc glmmod data=t; class g; model y1 = g; run;
title 'Q5 two models';
proc glmmod data=t; class h; model y1 = h; model y2 = h; run;
title 'Q8 intercept only';
proc glmmod data=t; model y1 = ; run;
title 'Q11 class var as response';
proc glmmod data=t; class h; model h = x; run;
title 'Q12 nested crossed and at';
proc glmmod data=t; class g h; model y1 = x(g) h*x(g) g|h|x@2; run;
title 'Q15 noint without effects';
proc glmmod data=t; model y1 = / noint; run;
