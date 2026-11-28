/* expect-rc: 2
   STAT-NLIN-001 boundary: PROC NLIN parses and validates the step, but only
   METHOD=MARQUARDT is verified against SAS output. The default METHOD=GAUSS
   iteration (STAT-NLIN-002/006) must fail visibly (D-009 gap) and print no
   table, never a plausible-looking listing. Data: invented. */
options nocenter;
title;
data growth;
input x y @@;
datalines;
1 2.1 2 3.9 3 6.2 4 7.8 5 10.1
;
proc nlin data=growth;
parms b=1;
model y = b*x;
run;
