/* FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. Full exact/common ticket acceptance remains pending. */
options nodate nonumber; ods graphics off;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / noprint senspec riskdiff relrisk; run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks cl=(ac ha mn newcombe wald)) relrisk(cl=(wald waldmodified score lr)) or(cl=(wald waldmodified score lr midp)); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks column=2 cl=(mn(correct=no) newcombe(correct) wald(correct))) relrisk(column=2 cl=(waldmodified score(correct=no) lr)); run;
