/* Two-way arm x response cross-tabulation */
data dm; input ARM $ RESP $; datalines;
DRUG Y
DRUG Y
DRUG N
PLACEBO N
PLACEBO Y
PLACEBO N
;
run;
proc freq data=dm; tables ARM*RESP; run;
