data d;
input x y f;
datalines;
1 1 0
1 2 9
2 1 11
2 2 3
;
proc corr polychoric; var x y; freq f; run;
data d;
input x y f;
datalines;
1 1 10
1 2 4
2 2 8
2 3 2
3 3 7
;
proc corr polychoric; var x y; freq f; run;
