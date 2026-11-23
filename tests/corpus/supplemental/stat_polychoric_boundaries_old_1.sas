%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 33
0 1 24
0 2 9
10 0 0
10 1 0
10 2 7
;
run;

%fit(old-1,1e-05,200);
data probe; input x y f; datalines;
0 0 280
0 20 0
2 0 273
2 20 161
12 0 0
12 20 189
;
run;

%fit(old-2,1e-06,200);
data probe; input x y f; datalines;
0 0 3500
0 -1 1600
0 -2 0
1 0 0
1 -1 2300
1 -2 1200
3 0 0
3 -1 0
3 -2 2400
;
run;

%fit(old-3,1e-05,200);
data probe; input x y f; datalines;
0 0 10
0 1 0
0 4 0
0 24 0
1 0 6
1 1 8
1 4 0
1 24 0
2 0 0
2 1 31
2 4 0
2 24 0
4 0 0
4 1 34
4 4 13
4 24 25
;
run;

%fit(old-4,1e-06,200);
data probe; input x y f; datalines;
0 0 245
0 20 28
0 23 0
10 0 0
10 20 175
10 23 231
;
run;

%fit(old-5,1e-05,200);
data probe; input x y f; datalines;
0 0 4000
0 -3 0
10 0 2500
10 -3 900
20 0 0
20 -3 3500
;
run;

%fit(old-6,1e-06,200);
data probe; input x y f; datalines;
0 0 18
0 20 0
0 21 0
2 0 36
2 20 19
2 21 0
4 0 0
4 20 20
4 21 24
;
run;

%fit(old-7,1e-05,200);
data probe; input x y f; datalines;
0 0 252
0 3 0
0 23 0
0 43 0
10 0 182
10 3 259
10 23 0
10 43 0
12 0 0
12 3 112
12 23 105
12 43 126
14 0 0
14 3 0
14 23 0
14 43 266
;
run;

%fit(old-8,1e-06,200);
data probe; input x y f; datalines;
0 0 2600
0 -20 2800
0 -21 0
2 0 0
2 -20 3200
2 -21 2400
;
run;

%fit(old-9,1e-05,200);
data probe; input x y f; datalines;
0 0 26
0 20 31
1 0 0
1 20 12
3 0 0
3 20 8
;
run;

%fit(old-10,1e-06,200);
data probe; input x y f; datalines;
0 0 266
0 1 0
0 4 0
1 0 259
1 1 0
1 4 0
11 0 175
11 1 133
11 4 14
;
run;

%fit(old-11,1e-05,200);
data probe; input x y f; datalines;
0 0 1800
0 -1 1800
0 -21 0
0 -22 0
1 0 0
1 -1 700
1 -21 3600
1 -22 0
11 0 0
11 -1 0
11 -21 1300
11 -22 3600
13 0 0
13 -1 0
13 -21 0
13 -22 3900
;
run;

%fit(old-12,1e-06,200);
data probe; input x y f; datalines;
0 0 34
0 20 0
0 21 0
2 0 2
2 20 16
2 21 18
;
run;

%fit(old-13,1e-05,200);
data probe; input x y f; datalines;
0 0 42
0 3 0
2 0 133
2 3 168
4 0 0
4 3 70
;
run;

%fit(old-14,1e-06,200);
data probe; input x y f; datalines;
0 0 3900
0 -1 0
0 -2 0
2 0 2100
2 -1 0
2 -2 0
3 0 900
3 -1 3200
3 -2 600
;
run;

%fit(old-15,1e-05,200);
data probe; input x y f; datalines;
0 0 30
0 20 16
0 21 0
0 41 0
2 0 0
2 20 20
2 21 0
2 41 0
3 0 0
3 20 33
3 21 0
3 41 0
13 0 0
13 20 21
13 21 18
13 41 13
;
run;

%fit(old-16,1e-06,200);
data probe; input x y f; datalines;
0 0 77
0 3 147
0 23 245
1 0 0
1 3 0
1 23 273
;
run;

%fit(old-17,1e-05,200);
data probe; input x y f; datalines;
0 0 800
0 -1 0
10 0 2200
10 -1 1500
12 0 0
12 -1 1000
;
run;

%fit(old-18,1e-06,200);
