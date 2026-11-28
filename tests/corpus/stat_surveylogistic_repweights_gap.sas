/* expect-rc: 2
   STAT-SURVEYLOGISTIC-001 remaining gap: the REPWEIGHTS statement
   (pp.9834-9836) needs replication variance estimation (BRR/jackknife,
   STAT-SURVEYLOGISTIC-009/010), not implemented yet; the step must fail
   visibly (D-009 gap) and print no table. Data: invented. */
options nodate nonumber nocenter linesize=160;
title;
data survey;
input stratum psu w r1 r2 y x;
datalines;
1 1 2 4 0 1 3
1 1 2 4 0 0 5
1 2 3 0 6 0 2
1 2 3 0 6 1 4
2 1 1 2 2 1 6
2 1 1 2 2 0 1
2 2 4 8 8 0 3
2 2 4 8 8 1 2
;
proc surveylogistic data=survey;
weight w;
repweights r1 r2;
model y(event='1')=x;
run;
