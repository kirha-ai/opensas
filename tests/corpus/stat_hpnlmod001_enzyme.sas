/* STAT-HPNLMOD-001: PROC HPNLMOD default listing of a least-squares fit
   (SAS/STAT 15.4 ch.63, PROC HPNLMOD statement pp.4863-4868). Data: the
   published enzyme sample of the NLIN/HPNLMOD chapters. Expected: the SAS
   reference listing of this program, except "Number of Threads", which is
   machine-specific and printed truthfully (opensas computes on 1 thread). */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data enzyme;
input conc rate @@;
datalines;
0.26 124.7 0.30 126.9 0.48 135.9 0.50 137.6 0.54 139.6 0.68 141.1 0.82 142.8 1.14 147.6 1.28 149.8 1.38 149.4 1.80 153.9 2.30 152.5 2.44 154.5 2.48 154.7
;
run;
proc hpnlmod data=enzyme;
parms theta1=160 theta2=0.1;
model rate ~ residual(theta1*conc/(theta2+conc));
run;
