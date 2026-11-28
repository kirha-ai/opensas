/* expect-rc: 2
   STAT-SURVEYFREQ-001 boundary: STRATA / LIST with several (or character)
   STRATA variables has unverified column rules and must fail visibly (D-009
   gap) without printing any table. Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data t;
input h c w a b @@;
datalines;
1 1 2 1 1 1 1 2 1 2 1 2 3 2 1 1 2 3 1 1 2 1 1 2 2 2 1 1 1 1 2 2 4 2 2 2 2 4 2 1 2 2 1 3 2 2 1 5 3 1
;
data t2; set t; length region $9; region=ifc(h=1,'north','southeast'); run;
title 'F2 LIST'; proc surveyfreq data=t2; strata region h / list; cluster c; weight w; tables a*b; run;
