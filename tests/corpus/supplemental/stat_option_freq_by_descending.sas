data sample;input g x y;datalines;
3 1 2
2 2 3
1 3 4
;
run;
proc freq data=sample; by descending g; tables x; run;
