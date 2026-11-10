/* FEAT-freq-tests: BY, n-way inference, empty/zero-margin strata and negative weights. */
options nodate nonumber; ods graphics off;
data cells; input b s r c w; datalines;
1 1 1 1 12
1 1 1 2 5
1 1 2 1 4
1 1 2 2 17
1 2 1 1 2
1 2 1 2 6
1 2 2 1 7
1 2 2 2 3
2 1 1 1 2
2 1 1 2 0
2 1 2 1 4
2 1 2 2 3
2 2 1 1 0
2 2 1 2 0
2 2 2 1 0
2 2 2 2 0
3 1 1 1 -1
3 1 1 2 3
3 1 2 1 4
3 1 2 2 5
;
proc freq data=cells; by b; weight w / zeros; tables s*r*c / list chisq measures(cl) scores=rank scorout; test gamma pcorr; run;
proc freq data=cells; by b; weight w / zeros; tables s*r*c / crosslist chisq(warn=none) noprint; run;
