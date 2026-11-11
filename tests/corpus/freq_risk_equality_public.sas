options nodate nonumber nosyntaxcheck; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(p=.2 var=null) alpha=.6; run;
proc freq data=b; weight w; tables x / noprint binomial(p=.2 var=null) alpha=.05; run;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / noprint riskdiff(column=both equal(null=10) var=null) relrisk(equal(null=2) printall) alpha=.6; run;
