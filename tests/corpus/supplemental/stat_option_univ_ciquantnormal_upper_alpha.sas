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

ods select Quantiles;
proc univariate data=sample ciquantnormal(type=upper alpha=.1); var x; run;
