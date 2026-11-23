%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
1000000000000.0 0 5
1000000000000.0 3 11
1000000000000.0 6 7
1000000000002.0 0 0
1000000000002.0 3 0
1000000000002.0 6 16
1000000000012.0 0 0
1000000000012.0 3 0
1000000000012.0 6 17
;
run;

%fit(old-19,1e-05,200);
data probe; input x y f; datalines;
0 0 224
0 3 0
0 6 0
0 26 0
2 0 70
2 3 196
2 6 77
2 26 0
12 0 0
12 3 0
12 6 56
12 26 147
14 0 0
14 3 0
14 6 0
14 26 217
;
run;

%fit(old-20,1e-06,200);
data probe; input x y f; datalines;
0 0 1800
0 -20 2800
0 -23 2800
10 0 0
10 -20 0
10 -23 3800
;
run;

%fit(old-21,1e-05,200);
data probe; input x y f; datalines;
0 0 10
0 1 32
10 0 0
10 1 38
20 0 0
20 1 10
;
run;

%fit(old-22,1e-06,200);
data probe; input x y f; datalines;
0 0 245
0 20 0
0 23 0
2 0 49
2 20 0
2 23 0
3 0 217
3 20 105
3 23 168
;
run;

%fit(old-23,1e-05,200);
data probe; input x y f; datalines;
0 0 2000
0 -1 1500
0 -21 0
0 -22 0
2 0 0
2 -1 3500
2 -21 0
2 -22 0
12 0 0
12 -1 1800
12 -21 0
12 -22 0
13 0 0
13 -1 3200
13 -21 2000
13 -22 600
;
run;

%fit(old-24,1e-06,200);
data probe; input x y f; datalines;
0 0 6
0 3 32
0 4 9
10 0 0
10 3 0
10 4 2
;
run;

%fit(old-25,1e-05,200);
data probe; input x y f; datalines;
0 0 35
0 3 0
10 0 280
10 3 0
20 0 252
20 3 266
;
run;

%fit(old-26,1e-06,200);
data probe; input x y f; datalines;
0 0 1200
0 -20 0
0 -40 0
10 0 3600
10 -20 3600
10 -40 0
11 0 0
11 -20 2600
11 -40 2100
;
run;

%fit(old-27,1e-05,200);
data probe; input x y f; datalines;
0 0 33
0 20 8
0 23 34
0 24 0
10 0 0
10 20 0
10 23 36
10 24 0
12 0 0
12 20 0
12 23 26
12 24 11
14 0 0
14 20 0
14 23 0
14 24 12
;
run;

%fit(old-28,1e-06,200);
data probe; input x y f; datalines;
1000000000000.0 0 196
1000000000000.0 3 35
1000000000000.0 23 203
1000000000001.0 0 0
1000000000001.0 3 0
1000000000001.0 23 175
;
run;

%fit(old-29,1e-05,200);
data probe; input x y f; datalines;
0 0 2100
0 -1 0
2 0 4000
2 -1 0
3 0 1600
3 -1 300
;
run;

%fit(old-30,1e-06,200);
data probe; input x y f; datalines;
0 0 8
0 20 0
0 21 0
10 0 5
10 20 34
10 21 0
20 0 0
20 20 25
20 21 5
;
run;

%fit(old-31,1e-05,200);
data probe; input x y f; datalines;
0 0 231
0 1 0
0 21 0
0 24 0
1 0 259
1 1 56
1 21 140
1 24 0
3 0 0
3 1 0
3 21 49
3 24 217
5 0 0
5 1 0
5 21 0
5 24 112
;
run;

%fit(old-32,1e-06,200);
data probe; input x y f; datalines;
0 0 900
0 -20 3100
0 -21 0
10 0 0
10 -20 2600
10 -21 500
;
run;

%fit(old-33,1e-05,200);
data probe; input x y f; datalines;
0 0 15
0 20 0
10 0 29
10 20 0
11 0 10
11 20 9
;
run;

%fit(old-34,1e-06,200);
data probe; input x y f; datalines;
0 0 252
0 3 0
0 6 0
1 0 280
1 3 231
1 6 0
3 0 0
3 3 35
3 6 154
;
run;

%fit(old-35,1e-05,200);
data probe; input x y f; datalines;
0 0 400
0 -20 0
0 -21 0
0 -41 0
10 0 3200
10 -20 3100
10 -21 0
10 -41 0
11 0 0
11 -20 1300
11 -21 1100
11 -41 0
13 0 0
13 -20 0
13 -21 2500
13 -41 1200
;
run;

%fit(old-36,1e-06,200);
