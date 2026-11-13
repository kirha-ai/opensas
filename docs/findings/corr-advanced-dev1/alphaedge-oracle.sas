data d;
input x y z w;
datalines;
1 2 1 1
2 5 1 2
3 . 1 3
4 6 1 1
5 8 1 2
;
proc corr alpha; var x y z; run;
proc corr alpha; var x y; weight w; run;
proc corr alpha nomiss; var x y z; run;
proc corr alpha; var x y; partial z; run;
proc corr alpha vardef=n; var x y; run;
proc corr spearman kendall; var x y; partial x; run;
proc corr singular=0; var x y; partial z; run;
