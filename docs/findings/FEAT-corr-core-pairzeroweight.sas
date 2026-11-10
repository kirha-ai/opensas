options nodate nonumber;
data d; input x y w; datalines;
1 2 0
2 3 -1
. 5 1
;
proc corr; var x y; weight w; run;
