data sample;input g1 g3 g2 x;datalines;
1 1 1 2
1 1 1 4
1 1 2 10
1 1 2 14
;
run;
proc univariate data=sample;by g2;by;var x;run;
