%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
-29 103 161
115 -133 7
-29 -35 301
115 103 70
101 103 210
-29 -133 42
-24 103 343
-29 71 399
;
run;

%fit(occupied-00-c0.99-m1,0.99,1);
%fit(occupied-00-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
-70 -136 3408
-70 127 96
119 -136 480
103 -136 2208
-30 -136 1488
119 127 912
119 33 960
119 -107 3312
;
run;

%fit(occupied-01-c0.99-m1,0.99,1);
%fit(occupied-01-c0.3-m2,0.3,2);
%fit(occupied-01-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-80 -74 210
109 3 434
109 -74 7
84 3 49
-80 -24 91
-80 3 35
-18 3 378
-80 -70 287
;
run;

%fit(occupied-02-c0.99-m1,0.99,1);
%fit(occupied-02-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
26 -108 3048
96 50 127
24 -108 8255
-16 -99 3048
96 -108 8890
-16 -23 8509
-16 -108 3175
-16 50 2159
;
run;

%fit(occupied-03-c0.99-m1,0.99,1);
%fit(occupied-03-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
34 93 5643
-1 114 594
-17 114 5940
-86 -116 297
34 -3 1881
-86 114 7029
34 114 693
34 -116 594
;
run;

%fit(occupied-04-c0.99-m1,0.99,1);
%fit(occupied-04-c0.3-m2,0.3,2);
%fit(occupied-04-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
41 -105 133
-59 106 49
-59 -105 182
-59 -75 434
41 106 7
31 -105 273
-16 -105 476
-59 30 392
;
run;

%fit(occupied-05-c0.99-m1,0.99,1);
%fit(occupied-05-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
49 92 23
-54 39 1219
-91 39 483
-91 53 207
-91 92 506
-91 77 1426
49 39 966
-45 39 1012
;
run;

%fit(occupied-06-c0.99-m1,0.99,1);
%fit(occupied-06-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
120 112 2159
120 -178 3429
23 -178 6477
-63 112 127
-63 -178 6858
120 97 9271
79 -178 9398
120 -106 2159
;
run;

%fit(occupied-07-c0.99-m1,0.99,1);
%fit(occupied-07-c0.3-m2,0.3,2);
