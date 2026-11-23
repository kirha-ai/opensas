%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
32 1 343
77 -57 252
-2 1 154
77 -98 427
77 -73 301
77 1 84
-2 -98 7
54 1 462
;
run;

%fit(occupied-08-c0.99-m1,0.99,1);
%fit(occupied-08-c0.3-m2,0.3,2);
%fit(occupied-08-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
38 -178 127
-52 36 9144
-52 -106 9017
6 79 3302
-49 79 9144
-52 -178 3556
-52 79 1778
38 79 2286
;
run;

%fit(occupied-09-c0.99-m1,0.99,1);
%fit(occupied-09-c0.3-m2,0.3,2);
%fit(occupied-09-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-54 -70 5256
-54 -31 3796
119 -31 73
109 -139 4015
-54 -136 1898
-40 -139 5183
-54 -139 1168
119 -139 2336
;
run;

%fit(occupied-10-c0.99-m1,0.99,1);
%fit(occupied-10-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
117 -157 352
117 87 11
-37 -157 550
-83 -107 594
-83 -5 770
-83 87 660
41 -157 671
-83 -157 121
;
run;

%fit(occupied-11-c0.99-m1,0.99,1);
data probe; input x y f; datalines;
96 -53 108
55 89 126
96 65 42
55 -145 2
96 -145 44
78 89 112
96 89 10
87 89 62
;
run;

%fit(occupied-12-c0.99-m1,0.99,1);
%fit(occupied-12-c0.3-m2,0.3,2);
%fit(occupied-12-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
102 -99 2448
102 44 1296
102 -46 3216
-76 53 2352
50 53 912
-76 -99 48
102 53 432
88 53 1728
;
run;

%fit(occupied-13-c0.99-m1,0.99,1);
%fit(occupied-13-c0.3-m2,0.3,2);
%fit(occupied-13-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-55 -33 7620
100 -85 9144
19 -85 2413
110 101 127
-55 -85 2032
-55 61 5588
-55 101 3175
110 -85 889
;
run;

%fit(occupied-14-c0.99-m1,0.99,1);
%fit(occupied-14-c0.3-m2,0.3,2);
%fit(occupied-14-c1e-06-m200,1e-06,200);
