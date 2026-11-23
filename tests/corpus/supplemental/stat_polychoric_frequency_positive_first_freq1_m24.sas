%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 35
11 0 25
12 0 18
23 0 15
23 19 33
23 23 31
23 27 14
;
run;

%fit(positive-first-freq1-m24,1e-06,24);
%fit(positive-first-freq1-m25,1e-06,25);
data probe; input x y f; datalines;
0 0 70
11 0 50
12 0 36
23 0 30
23 19 66
23 23 62
23 27 28
;
run;

%fit(positive-first-freq2-m24,1e-06,24);
%fit(positive-first-freq2-m25,1e-06,25);
data probe; input x y f; datalines;
0 0 105
11 0 75
12 0 54
23 0 45
23 19 99
23 23 93
23 27 42
;
run;

%fit(positive-first-freq3-m24,1e-06,24);
%fit(positive-first-freq3-m25,1e-06,25);
data probe; input x y f; datalines;
0 0 140
11 0 100
12 0 72
23 0 60
23 19 132
23 23 124
23 27 56
;
run;

%fit(positive-first-freq4-m24,1e-06,24);
%fit(positive-first-freq4-m25,1e-06,25);
data probe; input x y f; datalines;
0 0 175
11 0 125
12 0 90
23 0 75
23 19 165
23 23 155
23 27 70
;
run;

%fit(positive-first-freq5-m24,1e-06,24);
%fit(positive-first-freq5-m25,1e-06,25);
data probe; input x y f; datalines;
0 0 210
11 0 150
12 0 108
23 0 90
23 19 198
23 23 186
23 27 84
;
run;

%fit(positive-first-freq6-m24,1e-06,24);
%fit(positive-first-freq6-m25,1e-06,25);
data probe; input x y f; datalines;
0 0 280
11 0 200
12 0 144
23 0 120
23 19 264
23 23 248
23 27 112
;
run;

%fit(positive-first-freq8-m24,1e-06,24);
%fit(positive-first-freq8-m25,1e-06,25);
data probe; input x y f; datalines;
0 0 315
11 0 225
12 0 162
23 0 135
23 19 297
23 23 279
23 27 126
;
run;

%fit(positive-first-freq9-m24,1e-06,24);
%fit(positive-first-freq9-m25,1e-06,25);
data probe; input x y f; datalines;
0 0 350
11 0 250
12 0 180
23 0 150
23 19 330
23 23 310
23 27 140
;
run;

%fit(positive-first-freq10-m24,1e-06,24);
data probe; input x y f; datalines;
0 0 385
11 0 275
12 0 198
23 0 165
23 19 363
23 23 341
23 27 154
;
run;

%fit(positive-first-freq11-m24,1e-06,24);
