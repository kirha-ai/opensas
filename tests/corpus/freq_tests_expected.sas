/* FEAT-freq-tests: list/dataset order, aliases, expected columns and display-only limits. */
options nodate nonumber; ods graphics off;
data counts; input g w; datalines;
30 23
10 20
20 27
. 5
;
data prop; input TestPercent; datalines;
20
30
50
;
data prop2; input Percent; datalines;
20
30
50
;
data freq; input Frequency; datalines;
14
21
35
;
proc freq data=counts; weight w; tables g / chisq(lrchi testp=prop) missprint; run;
proc freq data=counts; weight w; tables g / chisq(testp=prop2) nopercent nocum maxlevels=2; run;
proc freq data=counts; weight w; tables g / chisq(lrchi testf=freq); run;
proc freq data=counts order=data; weight w; tables g / testp=(20 30) testp=(50) maxlevels=1; run;
proc freq data=counts; weight w; tables g / missing chisq(lrchi testp=(5 20 30 45)); run;
proc freq data=counts noprint; weight w; tables g / chisq(testp=prop warn=none); run;
