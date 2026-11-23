options nodate nonumber;
ods listing gpath="%sysfunc(pathname(work))";
data d; input x; datalines;
0.08
0.11
0.17
0.22
0.25
0.31
0.37
0.44
0.49
0.56
0.63
0.72
;
proc univariate data=d; var x; histogram x / beta; run;
