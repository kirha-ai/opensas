/* expect-rc: 2
   STAT-SURVEYLOGISTIC-001 boundary: CLASS effects (and FREQ, DOMAIN,
   replication methods, other links, models with several slopes) are owned by
   later SURVEYLOGISTIC tickets. The step must fail visibly (D-009 gap) and
   print no table at all. Data: invented. */
options nodate nonumber nocenter linesize=160;
title;
data survey;
input stratum psu w grp $ y;
datalines;
1 1 2 a 1
1 1 2 b 0
1 2 3 a 0
1 2 3 b 1
2 1 1 a 1
2 1 1 b 0
2 2 4 a 0
2 2 4 b 0
;
proc surveylogistic data=survey;
strata stratum;
cluster psu;
weight w;
class grp;
model y(event='1')=grp;
run;
