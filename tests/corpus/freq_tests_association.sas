/* FEAT-freq-tests: real-SAS evidence docs/findings/freq-tests/poly-precision.{txt,log}. */
options nodate nonumber; ods graphics off;
data cells; input r c w; datalines;
1 1 12
1 2 5
1 3 3
2 1 4
2 2 17
2 3 6
3 1 2
3 2 8
3 3 13
;
proc freq data=cells; weight w; tables r*c / chisq measures(cl) plcorr(converge=0.00000001); test measures plcorr; run;
data two; input r c w; datalines;
1 1 1
1 2 9
2 1 11
2 2 3
;
proc freq data=two; weight w; tables r*c / chisq measures(cl) plcorr(converge=0.00000001); test measures plcorr; run;
proc freq data=cells; weight w; tables r / chisq(lrchi testp=(20 30 50) df=-1); run;
