/* STAT-RSREG-001: default RSREG listing with LACKFIT on the chapter's
 * published Getting Started data (S154 pp.8865-8869): coding, fit summary,
 * Type I regression ANOVA, lack of fit, estimates (uncoded and coded),
 * factor ANOVA with labels, canonical analysis (minimum). Every token was
 * checked against the SAS 9.4 reference listing of the same program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Response Surface with a Simple Optimum';
data smell;
input Odor T R H @@;
label T = "Temperature" R = "Gas-Liquid Ratio" H = "Packing Height";
datalines;
66 40 .3 4 39 120 .3 4 43 40 .7 4 49 120 .7 4
58 40 .5 2 17 120 .5 2 -5 40 .5 6 -40 120 .5 6
65 80 .3 2 7 80 .7 2 43 80 .3 6 -22 80 .7 6
-31 80 .5 4 -35 80 .5 4 -26 80 .5 4
;
proc rsreg data=smell;
model Odor = T R H / lackfit;
run;
