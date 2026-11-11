/* FEAT-freq-risk numerical boundary acceptance; independent SAS evidence acceptance/boundaries-public.{sas,txt,log}. */
options nodate nonumber nosyntaxcheck; ods graphics off;
data allrow1; input r c w; datalines;
1 1 10
1 2 0
2 1 5
2 2 5
;
proc freq data=allrow1; weight w / zeros; tables r*c / noprint senspec or(cl=(score lr)) relrisk(cl=(score lr)) riskdiff(norisks cl=(wald ac ha mn newcombe)); run;
proc freq data=allrow1; weight w / zeros; tables r*c / noprint relrisk(column=2 cl=(wald waldmodified score lr)); run;
data zerorow2; input r c w; datalines;
1 1 5
1 2 5
2 1 0
2 2 10
;
proc freq data=zerorow2; weight w / zeros; tables r*c / noprint senspec or(cl=(score lr)) relrisk(cl=(score lr)) riskdiff(norisks cl=(wald ac ha mn newcombe)); run;
proc freq data=zerorow2; weight w / zeros; tables r*c / noprint relrisk(column=2 cl=(wald waldmodified score lr)); run;
data fractional; input r c w; datalines;
1 1 12.4
1 2 8.6
2 1 5.2
2 2 25.8
;
proc freq data=fractional; weight w / zeros; tables r*c / noprint senspec or(cl=(score lr)) relrisk(cl=(score lr)) riskdiff(norisks cl=(wald ac ha mn newcombe)); run;
proc freq data=fractional; weight w / zeros; tables r*c / noprint relrisk(column=2 cl=(wald waldmodified score lr)); run;
data extreme; input r c w; datalines;
1 1 1
1 2 999
2 1 2
2 2 998
;
proc freq data=extreme; weight w / zeros; tables r*c / noprint senspec or(cl=(score lr)) relrisk(cl=(score lr)) riskdiff(norisks cl=(wald ac ha mn newcombe)); run;
proc freq data=extreme; weight w / zeros; tables r*c / noprint relrisk(column=2 cl=(wald waldmodified score lr)); run;
