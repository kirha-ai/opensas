/* One-way frequency over pre-summarized counts (WEIGHT) */
data counts; input CAT : $12. n; datalines;
RESPONDER 18
NONRESPONDER 42
;
run;
proc freq data=counts;
  tables CAT / nocum;
  weight n;
run;
