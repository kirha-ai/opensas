/* expect-rc: 1
   STAT-CATMOD-005: a nested-by-value effect whose value is not a level of
   the nested variable is the SAS user error "The formatted value specified
   as a nested level for variable b is not in the data." (SAS reference
   run; SAS prints the Data Summary and profiles first, opensas computes
   before printing and shows no table). Values compare as BEST16 text, so a
   character value compares with the trimmed level text.
   Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data t;
input b a y w s $ @@;
datalines;
1 1 0 5 p 1 1 1 7 p 1 2 0 8 p 1 2 1 4 p 2 1 0 6 q 2 1 1 6 q 2 2 0 4 q 2 2 1 8 q
;
proc catmod data=t; weight w; response means; model y=b a(b=3); run;
proc catmod data=t; weight w; response means; model y=b a(b=1.5); run;
proc catmod data=t; weight w; response means; model y=s a(s='r'); run;
