options nodate nonumber; ods graphics off;
data t; input id r c w; datalines;
1 1 1 10
1 1 2 0
1 2 1 10
1 2 2 0
2 1 1 0
2 1 2 10
2 2 1 0
2 2 2 10
3 1 1 10
3 1 2 0
3 2 1 0
3 2 2 10
4 1 1 0
4 1 2 10
4 2 1 10
4 2 2 0
;
proc freq data=t; by id; weight w / zeros; tables r*c / noprint riskdiff(cl=mn) relrisk(cl=(score lr) equal method=score); run;
