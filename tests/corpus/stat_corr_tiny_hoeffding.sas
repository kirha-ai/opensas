options nodate nonumber;
data d; input x y g h; datalines;
1 1 0 0
2 2 0 1
;

proc corr data=d hoeffding; var x y; run;
