options nodate nonumber; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / binomial(noninf margin=.2) alpha=.6; run;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / riskdiff(noninf method=newcombe) relrisk(equiv method=score) alpha=.6; run;
