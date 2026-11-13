data d;
input x y;
datalines;
1 2
2 .
3 8
4 4
5 5
;
proc corr spearman; var x y; run;
data h;
input x y;
datalines;
1 1
2 2
;
proc corr kendall; var x y; run;
