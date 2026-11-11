/* SAS oracle i2_zero.sas: Q0 means missing I2, retained DF1. */
options nosyntaxcheck; ods graphics off;
data equal;
input s r c n;
datalines;
1 1 1 10
1 1 2 10
1 2 1 10
1 2 2 10
2 1 1 10
2 1 2 10
2 2 1 10
2 2 2 10
;
proc freq data=equal; tables s*r*c / cmh(i2 gailsimon mf bdt) noprint; weight n; run;
