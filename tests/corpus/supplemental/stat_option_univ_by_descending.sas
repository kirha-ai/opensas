data sample;input g x y;datalines;
3 1 2
2 2 3
1 3 4
;
run;
proc univariate data=sample; by descending g; var x; run;
