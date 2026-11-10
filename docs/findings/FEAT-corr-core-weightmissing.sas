options nodate nonumber;
data d; input x y w; datalines;
1 2 .
2 3 .
;
proc corr; var x y; weight w; run;
