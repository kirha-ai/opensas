%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
-83 -151 2117
-96 88 3869
31 88 73
-96 -151 876
-39 -151 4307
-96 -114 4891
31 -151 3723
-96 -19 2044
;
run;

%fit(upper-12-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
112 -133 374
9 -133 275
-54 54 66
42 -133 594
-54 -133 187
112 54 11
-54 -63 627
-54 -34 803
;
run;

%fit(upper-13-c0.99-m1,0.99,1);
data probe; input x y f; datalines;
-38 -30 1380
38 -92 184
-38 89 1495
82 -92 138
82 124 23
-38 -92 460
-38 124 437
-14 -92 1334
;
run;

%fit(upper-14-c0.99-m1,0.99,1);
%fit(upper-14-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
38 -10 989
38 -12 184
75 -12 529
88 -12 1610
105 49 23
38 17 1311
38 49 391
105 -12 1426
;
run;

%fit(upper-15-c0.99-m1,0.99,1);
data probe; input x y f; datalines;
97 77 48
97 -157 1632
90 -157 1824
-5 -157 2880
-61 22 3120
-61 77 288
-61 -157 960
-61 -156 3504
;
run;

%fit(upper-16-c0.99-m1,0.99,1);
%fit(upper-16-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
16 -176 374
-49 -46 451
86 -176 759
-49 -24 198
117 -176 385
-49 -147 803
117 -24 11
-49 -176 121
;
run;

%fit(upper-17-c0.99-m1,0.99,1);
data probe; input x y f; datalines;
116 10 1104
116 131 48
-84 131 816
-84 10 624
-75 10 2832
-84 123 960
-84 78 2688
57 10 3072
;
run;

%fit(upper-18-c0.99-m1,0.99,1);
data probe; input x y f; datalines;
118 126 11
59 -86 792
118 -86 110
104 -86 341
54 -86 231
54 51 308
54 126 231
54 -47 748
;
run;

%fit(upper-21-c0.99-m1,0.99,1);
%fit(upper-21-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
42 -144 66
-77 -144 253
-77 32 528
-77 -93 737
-70 -144 759
-77 65 495
-38 -144 66
42 65 11
;
run;

%fit(upper-22-c0.99-m1,0.99,1);
data probe; input x y f; datalines;
26 -62 8382
-59 -62 3175
-23 -62 5461
69 89 127
69 -62 1651
-59 89 2159
-59 -10 9017
-59 64 6350
;
run;

%fit(upper-23-c0.99-m1,0.99,1);
%fit(upper-23-c0.3-m2,0.3,2);
