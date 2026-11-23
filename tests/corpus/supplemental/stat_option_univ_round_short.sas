data sample;input x y z;datalines;
1.26 2.26 3.26
2.26 3.26 4.26
;
run;
ods select Moments;proc univariate data=sample round=1 .5;var x y z;run;
