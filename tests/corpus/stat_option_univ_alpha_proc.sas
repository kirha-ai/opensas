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
ods select BasicIntervals;proc univariate data=sample alpha=.1 cibasic;var x;run;
