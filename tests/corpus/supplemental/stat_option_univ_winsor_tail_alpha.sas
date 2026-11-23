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

ods select WinsorizedMeans;
proc univariate data=sample winsor=.25(alpha=.1 type=upper); var x; run;
