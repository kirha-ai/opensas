/* expect-rc: 0. FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. COMMON is now integrated; standalone EXACT remains with its owner. */
options nodate nonumber; ods graphics off;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / riskdiff(common); run;
