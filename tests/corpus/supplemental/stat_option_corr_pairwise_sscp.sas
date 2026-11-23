data sample;input x y w;datalines;
1 2 2
2 0 1
4 6 3
9 . 1
;
run;
proc corr data=sample sscp;var x;with y;weight w;run;
