%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 12320
0 1 9072
1 0 9460
1 1 6966
;
run;

%fit(independent-1-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 357280
0 1 263088
1 0 274340
1 1 202014
;
run;

%fit(independent-1-scale-29-m1,0.99,1);
data probe; input x y f; datalines;
0 0 505120
0 1 371952
1 0 387860
1 1 285606
;
run;

%fit(independent-1-scale-41-m1,0.99,1);
data probe; input x y f; datalines;
0 0 652960
0 1 480816
1 0 501380
1 1 369198
;
run;

%fit(independent-1-scale-53-m1,0.99,1);
data probe; input x y f; datalines;
0 0 751520
0 1 553392
1 0 577060
1 1 424926
;
run;

%fit(independent-1-scale-61-m1,0.99,1);
data probe; input x y f; datalines;
0 0 6776
0 1 3388
1 0 8536
1 1 4268
;
run;

%fit(independent-2-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 359128
0 1 179564
1 0 452408
1 1 226204
;
run;

%fit(independent-2-scale-53-m1,0.99,1);
data probe; input x y f; datalines;
0 0 399784
0 1 199892
1 0 503624
1 1 251812
;
run;

%fit(independent-2-scale-59-m1,0.99,1);
data probe; input x y f; datalines;
0 0 1296
0 1 3240
1 0 432
1 1 1080
;
run;

%fit(independent-3-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 2592
0 1 6480
1 0 864
1 1 2160
;
run;

%fit(independent-3-scale-2-m1,0.99,1);
data probe; input x y f; datalines;
0 0 2565
0 1 7790
1 0 2700
1 1 8200
;
run;

%fit(independent-4-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 105165
0 1 319390
1 0 110700
1 1 336200
;
run;

%fit(independent-4-scale-41-m1,0.99,1);
data probe; input x y f; datalines;
0 0 4165
0 1 1610
1 0 2618
1 1 1012
;
run;

%fit(independent-5-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 3250
0 1 350
1 0 1820
1 1 196
;
run;

%fit(independent-6-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 4183
0 1 2444
1 0 4005
1 1 2340
;
run;

%fit(independent-7-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 11094
0 1 6020
1 0 3870
1 1 2100
;
run;

%fit(independent-8-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 10400
0 1 7200
1 0 16770
1 1 11610
;
run;

%fit(independent-9-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 10260
0 1 972
1 0 7695
1 1 729
;
run;

%fit(independent-10-scale-1-m1,0.99,1);
