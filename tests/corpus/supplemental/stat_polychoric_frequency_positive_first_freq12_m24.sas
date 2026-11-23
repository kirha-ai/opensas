%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 420
11 0 300
12 0 216
23 0 180
23 19 396
23 23 372
23 27 168
;
run;

%fit(positive-first-freq12-m24,1e-06,24);
data probe; input x y f; datalines;
0 0 455
11 0 325
12 0 234
23 0 195
23 19 429
23 23 403
23 27 182
;
run;

%fit(positive-first-freq13-m24,1e-06,24);
data probe; input x y f; datalines;
0 0 560
11 0 400
12 0 288
23 0 240
23 19 528
23 23 496
23 27 224
;
run;

%fit(positive-first-freq16-m24,1e-06,24);
data probe; input x y f; datalines;
0 0 700
11 0 500
12 0 360
23 0 300
23 19 660
23 23 620
23 27 280
;
run;

%fit(positive-first-freq20-m24,1e-06,24);
data probe; input x y f; datalines;
0 0 875
11 0 625
12 0 450
23 0 375
23 19 825
23 23 775
23 27 350
;
run;

%fit(positive-first-freq25-m24,1e-06,24);
data probe; input x y f; datalines;
0 0 1750
11 0 1250
12 0 900
23 0 750
23 19 1650
23 23 1550
23 27 700
;
run;

%fit(positive-first-freq50-m24,1e-06,24);
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

%fit(positive-first-freq100-m24,1e-06,24);
data probe; input x y f; datalines;
11 0 25
12 0 18
23 0 15
23 19 33
23 23 31
23 27 14
0 0 35
;
run;

%fit(positive-rotated-freq1-m24,1e-06,24);
%fit(positive-rotated-freq1-m25,1e-06,25);
data probe; input x y f; datalines;
11 0 50
12 0 36
23 0 30
23 19 66
23 23 62
23 27 28
0 0 70
;
run;

%fit(positive-rotated-freq2-m24,1e-06,24);
%fit(positive-rotated-freq2-m25,1e-06,25);
data probe; input x y f; datalines;
11 0 75
12 0 54
23 0 45
23 19 99
23 23 93
23 27 42
0 0 105
;
run;

%fit(positive-rotated-freq3-m24,1e-06,24);
%fit(positive-rotated-freq3-m25,1e-06,25);
data probe; input x y f; datalines;
11 0 100
12 0 72
23 0 60
23 19 132
23 23 124
23 27 56
0 0 140
;
run;

%fit(positive-rotated-freq4-m24,1e-06,24);
%fit(positive-rotated-freq4-m25,1e-06,25);
data probe; input x y f; datalines;
11 0 125
12 0 90
23 0 75
23 19 165
23 23 155
23 27 70
0 0 175
;
run;

%fit(positive-rotated-freq5-m24,1e-06,24);
%fit(positive-rotated-freq5-m25,1e-06,25);
data probe; input x y f; datalines;
11 0 150
12 0 108
23 0 90
23 19 198
23 23 186
23 27 84
0 0 210
;
run;

%fit(positive-rotated-freq6-m24,1e-06,24);
