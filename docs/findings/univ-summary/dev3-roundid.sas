data d;input x;datalines;
-2.5
-1.5
0.5
2.5
;
proc univariate data=d round=1 nextrobs=2;var x;id x;run;
