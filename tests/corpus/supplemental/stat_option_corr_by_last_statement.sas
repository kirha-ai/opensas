data sample;input g h x;datalines;
2 2 1
1 2 3
2 1 4
1 1 8
;
run;
proc corr data=sample;by g;by descending h;var x;run;
