data sample; input x; datalines;
1
2
2
4
5
7
8
9
;
run;

ods select TrimmedMeans;
proc univariate data=sample trim=.25(alpha=.1 type=lower); var x; run;
