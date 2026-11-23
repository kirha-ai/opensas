%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
109 -98 20
-155 121 33
39 121 28
109 -104 27
109 -92 30
65 121 2
109 121 18
;
run;

%fit(projection-0496-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
-14 86 25
-179 -96 70
-179 -76 75
49 86 55
-179 -36 110
-179 86 60
77 86 125
;
run;

%fit(projection-0765-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
54 27 21
-162 27 23
-52 27 34
-162 -118 36
-162 20 44
-162 -104 16
-79 27 24
;
run;

%fit(projection-1261-c1e-06-m200,1e-06,200);
