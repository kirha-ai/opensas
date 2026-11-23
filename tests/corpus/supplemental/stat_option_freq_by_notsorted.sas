data sample;input g x y;datalines;
2 1 2
1 2 3
2 3 4
;
run;
proc freq data=sample; by g notsorted; tables x; run;
