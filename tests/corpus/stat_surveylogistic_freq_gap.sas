/* expect-rc: 2
   STAT-SURVEYLOGISTIC-001 remaining gap: FREQ (p.9820) without a CLUSTER
   statement (each replicated observation its own PSU) is not verified yet;
   the step must fail visibly (D-009 gap) and print no table. Data: invented. */
options nodate nonumber nocenter linesize=160;
title;
data survey;
input stratum psu w f y x;
datalines;
1 1 2 1 1 3
1 1 2 2 0 5
1 2 3 1 0 2
1 2 3 3 1 4
2 1 1 1 1 6
2 1 1 2 0 1
2 2 4 1 0 3
2 2 4 2 1 2
;
proc surveylogistic data=survey;
strata stratum;
weight w;
freq f;
model y(event='1')=x;
run;
