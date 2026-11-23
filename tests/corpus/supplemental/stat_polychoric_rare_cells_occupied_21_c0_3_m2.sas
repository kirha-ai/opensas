%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
117 -67 128
117 -129 46
-40 -129 74
117 102 86
117 123 28
-14 -129 144
-73 123 2
-73 -129 16
;
run;

%fit(occupied-21-c0.3-m2,0.3,2);
%fit(occupied-21-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-50 140 84
-55 -66 76
-55 140 34
115 -66 2
-55 -27 46
71 140 138
-55 -4 118
115 140 18
;
run;

%fit(occupied-22-c0.99-m1,0.99,1);
%fit(occupied-22-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
-29 103 210
-59 -159 63
53 -159 7
-59 103 105
-59 -18 84
-16 103 490
-59 -59 413
53 103 203
;
run;

%fit(occupied-23-c0.99-m1,0.99,1);
%fit(occupied-23-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
0 0 1
0 1 1
1 0 1
1 1 800000
;
run;

%fit(null-00-c0.99-m1,0.99,1);
%fit(null-00-c0.99-m200,0.99,200);
%fit(null-00-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
0 0 1
0 1 1
1 0 1
1 1 1500000
;
run;

%fit(null-01-c0.99-m1,0.99,1);
%fit(null-01-c0.99-m200,0.99,200);
%fit(null-01-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
0 0 1
0 1 1
1 0 1
1 1 1999997
;
run;

%fit(null-02-c0.99-m1,0.99,1);
%fit(null-02-c0.99-m200,0.99,200);
%fit(null-02-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
0 0 1
0 1 1
1 0 1
1 1 2500000
;
run;

%fit(null-03-c0.99-m1,0.99,1);
%fit(null-03-c0.99-m200,0.99,200);
%fit(null-03-c1e-06-m200,1e-06,200);
