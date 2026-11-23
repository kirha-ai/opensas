data sample;input x y a b;datalines;
1 2 0 1
2 4 1 3
4 3 3 4
6 8 2 0
7 5 8 1
8 9 4 2
;
run;
proc corr data=sample;var x y;partial a;partial b;run;
