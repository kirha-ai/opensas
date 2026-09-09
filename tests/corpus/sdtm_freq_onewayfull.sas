/* One-way frequency with cumulative columns (severity distribution) */
data ae; input AESEV $ @@; datalines;
MILD MILD SEVERE MODERATE MILD SEVERE
;
run;
proc freq data=ae; tables AESEV; run;
