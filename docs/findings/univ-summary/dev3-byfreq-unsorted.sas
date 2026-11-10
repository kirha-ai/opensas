data d;input g x f;datalines;
1 10 1
2 90 0
1 30 1
;
proc univariate data=d noprint;by g;var x;freq f;output out=o n=n;run;
