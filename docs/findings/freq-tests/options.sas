options nodate nonumber; ods graphics off;
data one; input x w; datalines;
1 20
2 27
3 23
;
data probs; input _testp_; datalines;
20
30
50
;
data freqs; input TestFrequency; datalines;
14
21
35
;
proc freq data=one; weight w; tables x / chisq(lrchi testp=probs); run;
proc freq data=one; weight w; tables x / chisq(lrchi testf=freqs); run;
proc freq data=one; weight w; tables x / chisq testp=(20 30 50); run;
data two; input r c w; datalines;
1 1 1
1 2 9
2 1 11
2 2 3
;
proc freq data=two; weight w; tables r*c / chisq(df=3); run;
data perfect; input r c w; datalines;
1 1 10
1 2 0
2 1 0
2 2 15
;
proc freq data=perfect; weight w / zeros; tables r*c / measures(cl) plcorr; test measures plcorr; run;
