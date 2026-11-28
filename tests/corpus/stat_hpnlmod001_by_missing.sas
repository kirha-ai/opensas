/* STAT-HPNLMOD-001: BY groups and missing values. Rows of the published
   enzyme sample split into two BY groups; group b has one missing response
   and one missing conc (read 9, used 7). Expected: SAS 9.4 / STAT 15.4
   listing of this program, except the machine-specific "Number of Threads"
   (printed truthfully: 1). */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data e2;
input g $ conc rate @@;
datalines;
b 0.26 124.7 b 0.30 126.9 b 0.48 135.9 b 0.50 . b 0.54 139.6 b 0.68 141.1 b 0.82 142.8 b 1.14 147.6 b . 149.8
a 1.38 149.4 a 1.80 153.9 a 2.30 152.5 a 2.44 154.5 a 2.48 154.7 a 0.26 124.7 a 0.50 137.6
;
proc sort data=e2; by g; run;
proc hpnlmod data=e2;
by g;
parms theta1=160 theta2=0.1;
model rate ~ residual(theta1*conc/(theta2+conc));
run;
