/* STAT-HPNLMOD-001: explicit PROC options. ALPHA=0.1 with NOITPRINT,
   NOPRINT, GCONV=1E-9 and ALPHA=0.025 on the published enzyme sample.
   Expected: SAS 9.4 / STAT 15.4 listing of this program (ALPHA= leaves the
   95% Parameter Estimates limits unchanged in SAS; NOPRINT prints nothing),
   except the machine-specific "Number of Threads" (printed truthfully: 1). */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data enzyme;
input conc rate @@;
datalines;
0.26 124.7 0.30 126.9 0.48 135.9 0.50 137.6 0.54 139.6 0.68 141.1 0.82 142.8 1.14 147.6 1.28 149.8 1.38 149.4 1.80 153.9 2.30 152.5 2.44 154.5 2.48 154.7
;
proc hpnlmod data=enzyme alpha=0.1 noitprint;
parms theta1=160 theta2=0.1;
model rate ~ residual(theta1*conc/(theta2+conc));
run;
proc hpnlmod data=enzyme noprint;
parms theta1=160 theta2=0.1;
model rate ~ residual(theta1*conc/(theta2+conc));
run;
proc hpnlmod data=enzyme gconv=1e-9;
parms theta1=160 theta2=0.1;
model rate ~ residual(theta1*conc/(theta2+conc));
run;
proc hpnlmod data=enzyme alpha=0.025;
parms theta1=160 theta2=0.1;
model rate ~ residual(theta1*conc/(theta2+conc));
run;
