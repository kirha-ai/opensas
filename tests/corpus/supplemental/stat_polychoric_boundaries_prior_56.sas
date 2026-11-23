%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 1200
0 19 500
0 38 2500
0 42 0
3 0 0
3 19 0
3 38 2500
3 42 2800
6 0 0
6 19 0
6 38 0
6 42 1900
17 0 0
17 19 0
17 38 0
17 42 2100
;
run;

%fit(prior-56,1e-06,200);
data probe; input x y f; datalines;
0 0 7
0 1 11
0 3 0
1 0 0
1 1 0
1 3 17
;
run;

%fit(prior-57,1e-06,200);
data probe; input x y f; datalines;
0 0 9
0 -1 0
2 0 13
2 -1 0
7 0 0
7 -1 21
;
run;

%fit(prior-58,1e-05,200);
data probe; input x y f; datalines;
0 0 7
0 1 11
0 3 0
1 0 0
1 1 0
1 3 17
;
run;

%fit(nested-59,0.99,1);
%fit(nested-60,0.99,2);
%fit(nested-61,0.99,3);
%fit(nested-62,0.99,4);
%fit(nested-63,0.99,5);
%fit(nested-64,0.99,6);
%fit(nested-65,0.99,7);
%fit(nested-66,0.99,8);
%fit(nested-67,0.99,9);
%fit(nested-68,0.99,10);
%fit(nested-69,0.99,12);
%fit(nested-70,0.99,200);
%fit(nested-71,0.0037,1);
%fit(nested-72,0.0037,2);
%fit(nested-73,0.0037,3);
