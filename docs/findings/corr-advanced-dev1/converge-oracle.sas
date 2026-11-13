data d;
input x y f;
datalines;
1 1 900
1 2 20
1 3 5
2 1 3
2 2 50
2 3 3
3 1 2
3 2 4
3 3 13
;
proc corr polychoric(converge=.01 maxiter=3); var x y; freq f; run;
proc corr polychoric(converge=.01 maxiter=4); var x y; freq f; run;
proc corr polychoric(converge=1e-8); var x y; freq f; run;
