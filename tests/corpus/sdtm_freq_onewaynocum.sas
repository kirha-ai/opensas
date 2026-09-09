/* One-way frequency without cumulative columns (tables / nocum) */
data dm; input ARM $ @@; datalines;
DRUG DRUG PLACEBO DRUG PLACEBO PLACEBO
;
run;
proc freq data=dm; tables ARM / nocum; run;
