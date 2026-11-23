%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 9
0 -1 0
2 0 13
2 -1 0
7 0 0
7 -1 21
;
run;

%fit(nested-200,3.7e-07,10);
%fit(nested-201,3.7e-07,12);
%fit(nested-202,3.7e-07,200);
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

%fit(reflected-4,1e-05,200);
data probe; input x y f; datalines;
0 0 3500
0 -1 1600
0 -2 0
-1 0 0
-1 -1 2300
-1 -2 1200
-3 0 0
-3 -1 0
-3 -2 2400
;
run;

%fit(reflected-5,1e-05,200);
data probe; input x y f; datalines;
0 0 3500
0 1 1600
0 2 0
1 0 0
1 1 2300
1 2 1200
3 0 0
3 1 0
3 2 2400
;
run;

%fit(reflected-6,1e-05,200);
data probe; input x y f; datalines;
0 0 1800
0 -20 2800
0 -23 2800
10 0 0
10 -20 0
10 -23 3800
;
run;

%fit(reflected-7,1e-05,200);
data probe; input x y f; datalines;
0 0 1800
0 -20 2800
0 -23 2800
-10 0 0
-10 -20 0
-10 -23 3800
;
run;

%fit(reflected-8,1e-05,200);
data probe; input x y f; datalines;
0 0 1800
0 20 2800
0 23 2800
10 0 0
10 20 0
10 23 3800
;
run;

%fit(reflected-9,1e-05,200);
