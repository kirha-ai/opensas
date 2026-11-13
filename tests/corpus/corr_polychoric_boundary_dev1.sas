data d;
input x y f;
datalines;
1 1 10
1 2 4
2 2 8
2 3 2
3 3 7
;
proc corr data=d polychoric; var x y; freq f; run;
proc corr data=d polychoric(converge=.001); var x y; freq f; run;
data labels;
input x y f;
datalines;
100 1 10
100 2 4
101 2 8
101 3 2
1000 3 7
;
proc corr data=labels polychoric; var x y; freq f; run;
proc corr data=labels polychoric(converge=.99 maxiter=1); var x y; freq f; run;
data other;
input x y f;
datalines;
1 1 5
1 2 7
2 2 8
2 3 3
3 3 12
;
proc corr data=other polychoric; var x y; freq f; run;
