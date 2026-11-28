/* expect-rc: 2
   STAT-PROBIT-001 boundary: the LOG10 OPTC model itself is fitted, but the
   PLOTS= graphs (STAT-PROBIT-012) and the OUTPUT data set (STAT-PROBIT-010)
   are not implemented. The step (the shape of the reference program) must
   fail visibly (D-009 gap) and print no table at all, never a listing with
   silently missing graphs or data set.
   Data: the published Getting Started sample of ch.100. */
options nocenter;
title;
data study;
input Dose Respond @@;
Number = 15;
datalines;
0 3 1.1 4 1.3 4 2.0 3 2.2 5 2.8 4
3.7 5 3.9 9 4.4 8 4.8 11 5.9 12 6.8 13
;
proc probit data=study log10 optc plots=(predpplot ippplot);
model respond/number=dose;
output out=new p=p_hat;
run;
