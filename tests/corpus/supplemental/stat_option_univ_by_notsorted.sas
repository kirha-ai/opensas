data sample;input g x y;datalines;
2 1 2
1 2 3
2 3 4
;
run;
proc univariate data=sample; by g notsorted; var x; run;
