/* FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. Full exact/common ticket acceptance remains pending. */
options nodate nonumber; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(cl=wilson(correct)); run;
proc freq data=b; weight w; tables x / noprint binomial(cl=wald(correct)); run;
data f; input x w; datalines;
1 1.9
2 8.7
;
proc freq data=f; weight w; tables x / noprint binomial; run;
data z; input r c w; datalines;
1 1 0
1 2 10
2 1 5
2 2 5
;
proc freq data=z; weight w / zeros; tables r*c / noprint or(cl=(wald waldmodified score lr)) relrisk(cl=(wald waldmodified score lr)); run;
