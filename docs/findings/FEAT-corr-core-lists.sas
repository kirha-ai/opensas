options nodate nonumber;
data d; input x y z f; datalines;
1 2 3 2.9
3 4 1 1
5 8 4 3
;
proc corr; var x; var y; run;
proc corr; var x; with y; with z; run;
proc corr; var x y; freq f; run;
