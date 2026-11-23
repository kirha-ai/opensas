%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
107 12 21
-99 -91 497
-99 12 413
-79 -170 420
-99 -170 35
-21 -170 441
-99 -118 308
107 -170 259
;
run;

%fit(upper-00-c0.99-m1,0.99,1);
%fit(upper-00-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
-31 -106 7366
-31 110 2159
28 -114 3683
101 110 381
-31 45 8636
-24 -114 7112
101 -114 6350
-31 -114 1651
;
run;

%fit(upper-01-c0.99-m1,0.99,1);
%fit(upper-01-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
-30 -147 2079
54 115 99
54 -147 1584
-30 -11 2772
-20 -147 4059
-30 -88 3762
51 -147 6435
-30 115 5544
;
run;

%fit(upper-02-c0.99-m1,0.99,1);
%fit(upper-02-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
-74 -53 6731
12 -100 5969
-74 39 3810
92 39 127
92 -100 4445
-74 -100 3175
-22 -100 5080
-74 -69 7620
;
run;

%fit(upper-03-c0.99-m1,0.99,1);
%fit(upper-03-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
63 -152 175
-38 -104 448
41 -152 315
113 97 7
-38 -152 77
113 -152 273
-38 -123 420
-38 97 231
;
run;

%fit(upper-04-c0.99-m1,0.99,1);
%fit(upper-04-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
-89 -7 1081
-64 -113 1518
81 -113 230
-89 23 1311
106 105 23
106 -113 805
-89 -113 552
-89 105 1104
;
run;

%fit(upper-06-c0.99-m1,0.99,1);
%fit(upper-06-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
77 -180 1533
104 93 73
-90 -180 657
-90 93 4088
-90 -58 1460
-90 -141 1898
7 -180 4964
104 -180 4453
;
run;

%fit(upper-07-c0.99-m1,0.99,1);
%fit(upper-07-c0.3-m2,0.3,2);
data probe; input x y f; datalines;
-78 -70 803
121 135 219
-78 135 3723
121 -144 4015
-78 -138 5402
25 -144 438
-78 -144 438
23 -144 1533
;
run;

%fit(upper-08-c0.99-m1,0.99,1);
data probe; input x y f; datalines;
7 -160 6435
-26 -160 3465
57 44 99
57 -160 2376
-64 44 2772
-64 -34 6831
-64 -88 4158
-64 -160 594
;
run;

%fit(upper-10-c0.99-m1,0.99,1);
data probe; input x y f; datalines;
9 -155 792
82 106 22
14 -155 715
4 -155 110
4 106 88
4 -122 704
82 -155 792
4 83 165
;
run;

%fit(upper-11-c0.99-m1,0.99,1);
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

%fit(upper-12-c0.99-m1,0.99,1);
