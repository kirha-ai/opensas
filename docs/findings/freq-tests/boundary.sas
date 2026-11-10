options nodate nonumber; ods graphics off;
data zero; input r c w; datalines;
1 1 0
1 2 9
2 1 11
2 2 3
;
proc freq data=zero; weight w / zeros; tables r*c / plcorr; test plcorr; run;
data equal; input r c w; datalines;
1 1 5
1 2 5
2 1 5
2 2 5
;
proc freq data=equal; weight w; tables r*c / measures(cl) plcorr; test measures plcorr; run;
proc freq data=zero; weight w / zeros; tables r*c / chisq(df=-1); run;
