/* STAT-RSREG-001: BY (S154 p.8874) with two identical groups of the
 * published Getting Started data: per-group pages with the BY line and
 * identical results; of two BY statements only the last is used.
 * Every token was checked against the SAS 9.4 reference listing.
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
data two; set smell; do g=1 to 2; output; end; run;
proc sort data=two; by g; run;
proc rsreg data=two;
by Odor;
by g;
model Odor = T R H / lackfit;
run;
