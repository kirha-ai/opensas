data sample;input x w;datalines;
1 1
2 1
2 1
4 1
5 1
7 1
8 1
9 1
;
run;

ods select TrimmedMeans ExtremeValues;
proc univariate data=sample all; var x; run;
