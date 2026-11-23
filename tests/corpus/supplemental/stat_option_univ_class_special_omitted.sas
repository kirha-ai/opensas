data sample;input g x;datalines;
.A 8
._ 2
.Z 12
. 5
.A 10
1 26
;
run;
ods select Moments;proc univariate data=sample;class g;var x;run;
