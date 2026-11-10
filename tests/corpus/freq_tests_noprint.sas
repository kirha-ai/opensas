/* FEAT-freq-tests: independent SAS evidence cli-noprint.{txt,log}. */
options nodate nonumber; ods graphics off;
data noprint; input noprint c w; datalines;
1 1 12
1 2 5
2 1 4
2 2 17
;
title 'HIDDEN PROC TITLE'; footnote 'HIDDEN PROC FOOTNOTE';
proc freq data=noprint noprint; weight w; tables noprint*c / chisq; run;
title 'VISIBLE TABLE STATS'; footnote 'VISIBLE TABLE FOOTNOTE';
proc freq data=noprint; weight w; tables noprint*c / chisq noprint; run;
title 'VISIBLE NAME'; footnote;
proc freq data=noprint; weight w; tables noprint / chisq; run;
