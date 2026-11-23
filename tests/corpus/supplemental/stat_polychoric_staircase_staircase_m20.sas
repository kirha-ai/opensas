%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
-9 -17 35
-9 -4 0
-9 8 0
-9 13 0
0 -17 17
0 -4 30
0 8 0
0 13 0
11 -17 0
11 -4 21
11 8 9
11 13 0
31 -17 0
31 -4 0
31 8 16
31 13 7
;
run;

%fit(staircase-m20,1e-06,20);
%fit(staircase-m200,1e-06,200);
data probe; input x y f; datalines;
-9 -17 256
-9 -4 384
-9 8 0
-9 13 0
0 -17 0
0 -4 688
0 8 0
0 13 0
11 -17 0
11 -4 144
11 8 560
11 13 560
31 -17 0
31 -4 0
31 8 0
31 13 304
;
run;

%fit(shifted-staircase-m20,1e-06,20);
data probe; input x y f; datalines;
117 -17 35
117 -4 0
117 8 0
117 13 0
81 -17 17
81 -4 30
81 8 0
81 13 0
37 -17 0
37 -4 21
37 8 9
37 13 0
-43 -17 0
-43 -4 0
-43 8 16
-43 13 7
;
run;

%fit(reflect-first-axis-m20,1e-06,20);
%fit(reflect-first-axis-m200,1e-06,200);
data probe; input x y f; datalines;
-9 -17 2240
-9 -4 0
-9 8 0
-9 13 0
0 -17 1344
0 -4 0
0 8 0
0 13 0
11 -17 3008
11 -4 0
11 8 0
11 13 0
31 -17 960
31 -4 2176
31 8 1792
31 13 832
;
run;

%fit(corner-m20,1e-06,20);
%fit(corner-m200,1e-06,200);
data probe; input x y f; datalines;
-17 151 2240
-17 133 1344
-17 111 3008
-17 71 960
-4 151 0
-4 133 0
-4 111 0
-4 71 2176
8 151 0
8 133 0
8 111 0
8 71 1792
13 151 0
13 133 0
13 111 0
13 71 832
;
run;

%fit(transpose-and-reflect-m20,1e-06,20);
%fit(transpose-and-reflect-m200,1e-06,200);
