/* expect-rc: 2
   STAT-SURVEYFREQ-001 boundary: replication variance estimation
   (VARMETHOD=JACKKNIFE, like BRR, BOOTSTRAP and REPWEIGHTS) is owned by later
   SURVEYFREQ tickets. The step must fail visibly (D-009 gap) and print no
   table at all, never Taylor-series standard errors under another method's
   name. Data: invented. */
options nodate nonumber nocenter linesize=160;
title;
data survey;
input stratum psu w a b;
datalines;
1 1 2 1 1
1 1 2 1 2
1 2 3 2 1
1 2 3 1 1
2 1 1 2 2
2 1 1 1 1
2 2 4 2 2
2 2 4 2 1
;
proc surveyfreq data=survey varmethod=jackknife;
strata stratum;
cluster psu;
weight w;
tables a*b / row;
run;
