%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
11 0 325
12 0 234
23 0 195
23 -19 429
23 -23 403
23 -27 182
0 0 455
;
run;

%fit(reflect-y-rotated-freq13-m24,1e-06,24);
data probe; input x y f; datalines;
11 0 400
12 0 288
23 0 240
23 -19 528
23 -23 496
23 -27 224
0 0 560
;
run;

%fit(reflect-y-rotated-freq16-m24,1e-06,24);
data probe; input x y f; datalines;
11 0 500
12 0 360
23 0 300
23 -19 660
23 -23 620
23 -27 280
0 0 700
;
run;

%fit(reflect-y-rotated-freq20-m24,1e-06,24);
data probe; input x y f; datalines;
11 0 625
12 0 450
23 0 375
23 -19 825
23 -23 775
23 -27 350
0 0 875
;
run;

%fit(reflect-y-rotated-freq25-m24,1e-06,24);
data probe; input x y f; datalines;
11 0 1250
12 0 900
23 0 750
23 -19 1650
23 -23 1550
23 -27 700
0 0 1750
;
run;

%fit(reflect-y-rotated-freq50-m24,1e-06,24);
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

%fit(reflect-y-rotated-freq100-m24,1e-06,24);
