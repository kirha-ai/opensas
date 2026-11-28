/* expect-rc: 2
   STAT-HPNLMOD-001 boundary: programming statements (STAT-HPNLMOD-009) are
   recognised but not implemented. The step must fail visibly (D-009 gap) and
   print nothing. Data: the published enzyme sample. */
options nocenter;
title;
data enzyme;
input conc rate @@;
datalines;
0.26 124.7 0.30 126.9 0.48 135.9 0.50 137.6 0.54 139.6 0.68 141.1 0.82 142.8
;
proc hpnlmod data=enzyme;
parms theta1=160 theta2=0.1;
pred = theta1*conc/(theta2+conc);
model rate ~ residual(pred);
run;
