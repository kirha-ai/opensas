%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
98 -42 32
-26 118 10
-26 -99 1
-24 118 69
98 -99 42
98 9 72
83 118 35
98 118 18
;
run;

%fit(occupied-15-c0.99-m1,0.99,1);
%fit(occupied-15-c0.3-m2,0.3,2);
%fit(occupied-15-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-55 106 7747
-72 -97 6731
-16 106 8890
76 106 1143
-72 44 7366
76 -97 127
-72 106 2413
-72 33 9144
;
run;

%fit(occupied-16-c0.99-m1,0.99,1);
%fit(occupied-16-c0.3-m2,0.3,2);
%fit(occupied-16-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
111 -2 2871
-78 -79 4257
111 -79 792
-78 58 99
-19 -79 7227
111 -67 6633
111 58 2772
105 -79 2574
;
run;

%fit(occupied-17-c0.99-m1,0.99,1);
%fit(occupied-17-c0.3-m2,0.3,2);
%fit(occupied-17-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
114 -165 1881
114 -77 5742
114 24 7128
114 71 792
113 -165 6930
-29 71 99
-29 -165 2970
52 -165 2277
;
run;

%fit(occupied-18-c0.99-m1,0.99,1);
%fit(occupied-18-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
15 100 385
35 100 440
40 67 792
40 100 66
40 36 264
19 100 121
15 36 11
40 42 231
;
run;

%fit(occupied-19-c0.99-m1,0.99,1);
%fit(occupied-19-c0.3-m2,0.3,2);
%fit(occupied-19-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
40 -154 176
-33 -154 528
-98 -154 110
-98 32 11
40 -93 748
40 32 748
40 -105 583
-94 -154 572
;
run;

%fit(occupied-20-c0.99-m1,0.99,1);
%fit(occupied-20-c0.3-m2,0.3,2);
%fit(occupied-20-c1e-06-m200,1e-06,200);
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

%fit(occupied-21-c0.99-m1,0.99,1);
