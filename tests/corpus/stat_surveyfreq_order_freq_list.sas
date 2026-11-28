/* STAT-SURVEYFREQ-001: ORDER=FREQ (descending unweighted frequency) and STRATA / LIST
   (Stratum Information table) for one numeric STRATA variable.
   Expected listing: real SAS 9.4 / SAS/STAT 15.4 run of this program
   (batched reference run, 2026-11-28). Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data t;
input h c w a b @@;
datalines;
1 1 2 1 1 1 1 2 1 2 1 2 3 2 1 1 2 3 1 1 2 1 1 2 2 2 1 1 1 1 2 2 4 2 2 2 2 4 2 1 2 2 1 3 2 2 1 5 3 1
;
data t2; set t; length region $9; region=ifc(h=1,'north','southeast'); run;
title 'F1 FREQ'; proc surveyfreq data=t order=freq; strata h; cluster c; weight w; tables a*b; run;
title 'F3 LIST1'; proc surveyfreq data=t; strata h / list; cluster c; weight w; tables a*b; run;
