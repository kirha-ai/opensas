%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 1
0 1 1
1 0 1
1 1 4000000
;
run;

%fit(null-04-c0.99-m1,0.99,1);
%fit(null-04-c0.99-m200,0.99,200);
%fit(null-04-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
0 0 1
0 1 1
1 0 1
1 1 8000000
;
run;

%fit(null-05-c0.99-m1,0.99,1);
%fit(null-05-c0.99-m200,0.99,200);
%fit(null-05-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
0 0 1
0 1 1
1 0 1
1 1 16000000
;
run;

%fit(null-06-c0.99-m1,0.99,1);
%fit(null-06-c0.99-m200,0.99,200);
%fit(null-06-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
0 0 1
0 1 2
1 0 3
1 1 8000000
;
run;

%fit(null-07-c0.99-m1,0.99,1);
%fit(null-07-c0.99-m200,0.99,200);
%fit(null-07-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
0 0 2
0 1 4
1 0 3
1 1 13000000
;
run;

%fit(null-08-c0.99-m1,0.99,1);
%fit(null-08-c0.99-m200,0.99,200);
%fit(null-08-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
0 0 8700000
0 1 3
1 0 2
1 1 1
;
run;

%fit(null-09-c0.99-m1,0.99,1);
%fit(null-09-c0.99-m200,0.99,200);
%fit(null-09-c1e-06-m200,1e-06,200);
