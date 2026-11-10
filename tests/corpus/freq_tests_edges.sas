/* FEAT-freq-tests: real-SAS evidence docs/findings/freq-tests/edges.{txt,log}. */
options nodate nonumber; ods graphics off;
data ties; input r c w; datalines;
1 1 4
1 2 4
1 3 2
2 1 4
2 2 4
2 3 2
3 1 2
3 2 2
3 3 4
;
proc freq data=ties; weight w; tables r*c / measures(cl) chisq(df=-1); test measures; run;
data frac; input r c w; datalines;
1 1 1.9
1 2 9.7
2 1 11.4
2 2 3.8
;
proc freq data=frac; weight w; tables r*c / chisq measures; run;
data zero; input r c w; datalines;
1 1 0
1 2 9
2 1 11
2 2 3
;
proc freq data=zero; weight w / zeros; tables r*c / chisq measures(cl) plcorr(adjust); test plcorr; run;
proc freq data=ties; weight w; tables r*c / plcorr(maxiter=1); test plcorr; run;
data margin; input r c w; datalines;
1 1 0
1 2 0
2 1 3
2 2 5
3 1 4
3 2 1
;
proc freq data=margin; weight w / zeros; tables r*c / chisq measures(cl) plcorr; run;
