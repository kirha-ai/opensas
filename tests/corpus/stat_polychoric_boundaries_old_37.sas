%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 28
0 1 0
0 21 0
10 0 3
10 1 29
10 21 37
;
run;

%fit(old-37,1e-05,200);
data probe; input x y f; datalines;
0 0 112
0 20 0
10 0 42
10 20 196
12 0 0
12 20 280
;
run;

%fit(old-38,1e-06,200);
data probe; input x y f; datalines;
0 0 2800
0 -20 0
0 -40 0
2 0 2400
2 -20 700
2 -40 0
4 0 0
4 -20 3200
4 -40 400
;
run;

%fit(old-39,1e-05,200);
data probe; input x y f; datalines;
0 0 13
0 20 0
0 40 0
0 43 0
1 0 5
1 20 10
1 40 0
1 43 0
2 0 0
2 20 33
2 40 15
2 43 14
4 0 0
4 20 0
4 40 0
4 43 5
;
run;

%fit(old-40,1e-06,200);
data probe; input x y f; datalines;
0 0 32
0 4 34
0 5 10
1 0 0
1 4 0
1 5 33
;
run;

%fit(prior-41,1e-05,200);
data probe; input x y f; datalines;
0 0 33
0 1 308
11 0 0
11 1 286
14 0 0
14 1 297
;
run;

%fit(prior-42,1e-06,200);
data probe; input x y f; datalines;
0 0 420
0 -19 180
0 -20 0
3 0 0
3 -19 300
3 -20 168
6 0 0
6 -19 0
6 -20 324
;
run;

%fit(prior-43,1e-05,200);
data probe; input x y f; datalines;
0 0 2800
0 4 1100
0 23 600
0 24 0
11 0 0
11 4 0
11 23 1600
11 24 0
12 0 0
12 4 0
12 23 1300
12 24 0
23 0 0
23 4 0
23 23 900
23 24 2500
;
run;

%fit(prior-44,1e-06,200);
data probe; input x y f; datalines;
0 0 13
0 1 0
0 2 0
1 0 11
1 1 26
1 2 18
;
run;

%fit(prior-45,1e-05,200);
data probe; input x y f; datalines;
0 0 319
0 -19 0
3 0 352
3 -19 374
6 0 0
6 -19 319
;
run;

%fit(prior-46,1e-06,200);
data probe; input x y f; datalines;
0 0 300
0 4 0
0 5 0
1 0 420
1 4 180
1 5 396
4 0 0
4 4 0
4 5 396
;
run;

%fit(prior-47,1e-05,200);
data probe; input x y f; datalines;
0 0 29
0 -4 11
0 -8 34
11 0 0
11 -4 0
11 -8 18
;
run;

%fit(prior-49,1e-05,200);
data probe; input x y f; datalines;
0 0 99
0 1 0
3 0 297
3 1 143
4 0 0
4 1 330
;
run;

%fit(prior-50,1e-06,200);
data probe; input x y f; datalines;
0 0 420
0 4 180
0 5 0
11 0 0
11 4 144
11 5 408
14 0 0
14 4 0
14 5 228
;
run;

%fit(prior-51,1e-05,200);
data probe; input x y f; datalines;
0 0 800
0 -4 3000
0 -8 0
0 -27 0
1 0 0
1 -4 2200
1 -8 0
1 -27 0
2 0 0
2 -4 1100
2 -8 500
2 -27 0
5 0 0
5 -4 0
5 -8 1100
5 -27 1900
;
run;

%fit(prior-52,1e-06,200);
data probe; input x y f; datalines;
0 0 7
0 4 0
0 23 0
3 0 29
3 4 14
3 23 25
;
run;

%fit(prior-53,1e-05,200);
data probe; input x y f; datalines;
0 0 22
0 1 374
1 0 0
1 1 209
2 0 0
2 1 220
;
run;

%fit(prior-54,1e-06,200);
data probe; input x y f; datalines;
0 0 204
0 -1 108
0 -5 0
11 0 0
11 -1 324
11 -5 0
14 0 0
14 -1 36
14 -5 36
;
run;

%fit(prior-55,1e-05,200);
