options nodate nonumber;
data d; input x y g h; datalines;
1 2 0 0
1 2 0 0
1 3 0 1
1 3 0 1
1 4 1 0
1 4 1 0
;

proc corr data=d; var x y; run; proc freq data=d; tables g*h; run; proc univariate data=d; var x; run;
