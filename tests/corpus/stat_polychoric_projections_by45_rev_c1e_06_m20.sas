%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
1 13 9
3 13 7
3 10 10
5 10 13
5 7 14
7 7 5
7 4 11
7 1 7
;
run;

%fit(by45-rev-c1e-06-m20,1e-06,20);
%fit(by45-rev-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 -2 9
3 -2 7
3 1 10
5 1 13
5 4 14
7 4 5
7 7 11
9 7 7
9 10 13
;
run;

%fit(by55-c1e-06-m20,1e-06,20);
%fit(by55-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 13 9
3 13 7
3 10 10
5 10 13
5 7 14
7 7 5
7 4 11
9 4 7
9 1 13
;
run;

%fit(by55-rev-c1e-06-m20,1e-06,20);
%fit(by55-rev-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
124 21 87
124 -63 39
-19 145 54
4 145 60
124 -100 60
124 145 66
-171 145 129
;
run;

%fit(projection-0000-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-142 13 38
-142 73 4
41 88 14
83 88 10
-24 88 16
-142 19 22
-142 88 26
;
run;

%fit(projection-0001-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
94 -133 9
94 -100 7
-18 -133 35
-66 -133 25
94 -129 38
18 -133 22
94 36 40
;
run;

%fit(projection-0002-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-145 59 209
-145 -42 143
-145 -94 858
-117 -94 396
-145 -89 33
-136 -94 319
23 -94 484
;
run;

%fit(projection-0003-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-175 143 7
-57 143 31
25 143 12
-128 143 36
-175 -7 41
-175 -123 18
-175 56 16
;
run;

%fit(projection-0009-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-130 4 31
-130 -40 7
81 -148 18
-130 -110 8
96 -148 19
36 -148 21
-130 -148 18
;
run;

%fit(projection-0011-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-85 120 96
-37 120 114
-14 -49 117
-65 120 117
-14 120 150
-14 -55 39
-14 -11 30
;
run;

%fit(projection-0012-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-188 -126 123
-48 -109 51
-125 -126 12
-149 -126 108
-48 -68 93
-48 71 84
-48 -126 27
;
run;

%fit(projection-0042-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-198 -46 28
-198 -131 20
-198 66 40
-119 -131 37
-92 -131 8
68 -131 25
-198 -100 16
;
run;

%fit(projection-0175-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
138 54 90
138 -67 72
74 -67 51
138 -65 126
-76 -67 96
-140 -67 93
138 29 93
;
run;

%fit(projection-0238-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-200 -146 168
-152 -146 312
109 -139 232
109 46 296
109 -146 168
90 -146 104
109 25 176
;
run;

%fit(projection-0258-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-145 22 23
73 -51 34
-145 -51 21
2 -51 36
-145 118 23
103 -51 20
-145 -50 27
;
run;

%fit(projection-0279-c1e-06-m200,1e-06,200);
