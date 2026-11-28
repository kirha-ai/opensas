/* STAT-ROBUSTREG-001: the default M-estimation listing (bisquare weights,
 * SCALE=MED, H1 covariance) and the DIAGNOSTICS table with an ID variable on
 * the stack-loss data published in the SAS/STAT User's Guide (Chapter 107
 * Getting Started). Expected listing: SAS 9.4 for exactly these steps (the
 * originals add LEVERAGE, TEST and PLOTS=, which remain gaps here).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data Stack;
input x1 x2 x3 y exp $ @@;
datalines;
80 27 89 42 e1 80 27 88 37 e2
75 25 90 37 e3 62 24 87 28 e4
62 22 87 18 e5 62 23 87 18 e6
62 24 93 19 e7 62 24 93 20 e8
58 23 87 15 e9 58 18 80 14 e10
58 18 89 14 e11 58 17 88 13 e12
58 18 82 11 e13 58 19 93 12 e14
50 18 89 8 e15 50 18 86 7 e16
50 19 72 8 e17 50 19 79 8 e18
50 20 80 9 e19 56 20 82 15 e20
70 20 91 15 e21
;
proc robustreg data=stack;
model y = x1 x2 x3;
run;
proc robustreg data=stack;
model y = x1 x2 x3 / diagnostics;
id exp;
run;
proc robustreg data=stack;
model y = x1;
run;
