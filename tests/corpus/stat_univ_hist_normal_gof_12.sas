options nodate nonumber;
ods listing gpath="%sysfunc(pathname(work))";
data d; input x; datalines;
0.2
0.7
1.1
1.6
2.4
2.9
3.1
4.6
5.0
5.8
6.4
7.2
;
proc univariate data=d; var x; histogram x / normal; run;
