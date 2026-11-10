options nodate nonumber;
data d; input x y f; datalines;
1 2 0
2 3 .
;
proc corr; var x y; freq f; run;
