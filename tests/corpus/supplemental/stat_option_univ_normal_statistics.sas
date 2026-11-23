data sample;input x;datalines;
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
ods select TestsForNormality;proc univariate data=sample normal;var x;run;
