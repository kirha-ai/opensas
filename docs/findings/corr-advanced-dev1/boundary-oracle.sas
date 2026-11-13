data d;
input x y z;
z2=2*z; neg=-x; constant=1;
datalines;
1 2 1
2 5 3
3 5 2
4 9 4
5 8 3
6 13 5
7 12 4
8 17 6
;
proc corr data=d fisher; var x neg constant; run;
proc corr data=d pearson spearman kendall fisher; var x y; partial z z2 constant; run;
proc corr data=d fisher(type=upper rho0=-.5); var x; with y; run;
data poly;
input x y f;
datalines;
1 1 12
1 2 5
1 3 3
2 1 4
2 2 17
2 3 6
3 1 2
3 2 8
3 3 13
;
proc corr data=poly polychoric; var x y; freq f; run;
proc corr data=poly polyserial; var x; with y; freq f; run;
proc corr data=poly polychoric(maxiter=1); var x y; freq f; run;
