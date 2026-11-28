/* STAT-SURVEYFREQ-001: two strata of two clusters with unequal weights and a
   finite population correction (TOTAL=8 clusters per stratum, f = 2/8).
   Expected numbers come from an independent calculation of the Taylor-series
   formulas (between-cluster variance of the linearized totals within strata,
   times 1 - f), not from opensas output: e.g. cell (1,1) has cluster totals
   2, 3 | 1, 0, so V = 0.75 (2*0.5 + 2*0.5) = 1.5 and Std Err 1.22474.
   Data: invented. */
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
proc surveyfreq data=survey total=8;
strata stratum;
cluster psu;
weight w;
tables a*b / row;
run;
