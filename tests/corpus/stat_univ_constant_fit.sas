options nodate nonumber;
ods listing gpath="%sysfunc(pathname(work))";
data d; input x y g h; datalines;
1 2 0 0
1 2 0 0
1 3 0 1
1 3 0 1
1 4 1 0
1 4 1 0
;

proc univariate data=d; var x; histogram x / normal; run;
