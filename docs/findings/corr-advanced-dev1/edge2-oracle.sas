data d;
input x y f;
z=1;
datalines;
1 3 2
1 1 1
2 2 3
3 3 1
4 1 2
;
proc corr spearman kendall hoeffding; var x y z; freq f; run;
proc corr alpha; var x y; run;
proc corr alpha; var x; run;
data d;
input x y f;
datalines;
1 1 10
2 2 10
3 3 10
;
proc corr polychoric; var x y; freq f; run;
proc corr polyserial; var x; with y; freq f; run;
data d;
input x y f;
datalines;
1 1 50
1 2 2
1 3 1
2 1 2
2 2 20
2 3 1
3 1 1
3 2 2
3 3 10
;
proc corr polychoric(converge=1e-8 maxiter=200) polyserial(converge=1e-8); var x; with y; freq f; run;
