data d;input x y f;datalines;
0 0 280
2 0 273
2 20 161
12 20 189
;
proc corr data=d polychoric(converge=.00045 maxiter=14);var x;with y;freq f;run;
proc corr data=d polychoric(converge=.00038 maxiter=15);var x;with y;freq f;run;
data a;input x y f;datalines;
0 0 17
0 20 4
2 0 23
2 20 14
12 0 3
12 20 29
;
proc corr data=a polychoric;var x;with y;freq f;run;
data b;input x y f;datalines;
0 0 26
0 3 13
0 23 4
7 0 3
7 3 18
7 23 31
;
proc corr data=b polychoric(converge=1e-6);var x;with y;freq f;run;
data c;input x y f;datalines;
0 0 11
0 2 4
0 7 3
1 0 5
1 2 17
1 7 6
9 0 2
9 2 7
9 7 19
;
proc corr data=c polychoric;var x;with y;freq f;run;
data e;input x y f;datalines;
-1 2 14
-1 11 9
3 2 6
3 11 23
;
proc corr data=e polychoric(converge=1e-6);var x;with y;freq f;run;
