/* STAT-SURVEYFREQ-001: TABLES variable column widths: short names (width 5 for
   "Total"), wide numeric levels, a character length wider than its values,
   NOMCAR without missing values, a short VARHEADER=LABEL label.
   Expected listing: real SAS 9.4 / SAS/STAT 15.4 run of this program
   (batched reference run, 2026-11-28). Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data t;
input h c w a b @@;
datalines;
1 1 2 1 1 1 1 2 1 2 1 2 3 2 1 1 2 3 1 1 2 1 1 2 2 2 1 1 1 1 2 2 4 2 2 2 2 4 2 1
;
data t2; set t; if _n_=1 then a=123456; label a='A'; run;
data t3; set t; length s $7; s=ifc(a=1,'one','twothre'); run;
proc format; value bf 1='low' 2='highest'; run;
title 'E1 SHORT'; proc surveyfreq data=t; strata h; cluster c; weight w; tables a*b; run;
title 'E2 WIDE'; proc surveyfreq data=t2; strata h; cluster c; weight w; tables a*b; run;
title 'E3 CHARWIDE'; proc surveyfreq data=t3; strata h; cluster c; weight w; tables s*b; run;
title 'E5 NOMCARNOMISS'; proc surveyfreq data=t nomcar; strata h; cluster c; weight w; tables a*b; run;
title 'E7 LABELSHORT'; proc surveyfreq data=t2 varheader=label; strata h; cluster c; weight w; tables b*a; run;
