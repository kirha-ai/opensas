%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 3500
11 0 2500
12 0 1800
23 0 1500
23 19 3300
23 23 3100
23 27 1400
;
run;

%fit(positive-first-m24,1e-06,24);
data probe; input x y f; datalines;
11 0 2500
12 0 1800
23 0 1500
23 19 3300
23 23 3100
23 27 1400
0 0 3500
;
run;

%fit(positive-rotated-m24,1e-06,24);
data probe; input x y f; datalines;
0 0 3500
-11 0 2500
-12 0 1800
-23 0 1500
-23 19 3300
-23 23 3100
-23 27 1400
;
run;

%fit(reflect-x-first-m24,1e-06,24);
data probe; input x y f; datalines;
-11 0 2500
-12 0 1800
-23 0 1500
-23 19 3300
-23 23 3100
-23 27 1400
0 0 3500
;
run;

%fit(reflect-x-rotated-m24,1e-06,24);
data probe; input x y f; datalines;
0 0 3500
11 0 2500
12 0 1800
23 0 1500
23 -19 3300
23 -23 3100
23 -27 1400
;
run;

%fit(reflect-y-first-m24,1e-06,24);
data probe; input x y f; datalines;
11 0 2500
12 0 1800
23 0 1500
23 -19 3300
23 -23 3100
23 -27 1400
0 0 3500
;
run;

%fit(reflect-y-rotated-m24,1e-06,24);
