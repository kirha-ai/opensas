%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
1 -2 9
3 -2 7
3 1 10
5 1 13
5 4 14
;
run;

%fit(control3-c1e-06-m20,1e-06,20);
%fit(control3-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 7 9
3 7 7
3 4 10
5 4 13
5 1 14
;
run;

%fit(control3-rev-c1e-06-m20,1e-06,20);
%fit(control3-rev-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 -2 9
3 -2 7
3 1 10
5 1 13
5 4 14
5 7 5
;
run;

%fit(by34-c1e-06-m20,1e-06,20);
%fit(by34-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 10 9
3 10 7
3 7 10
5 7 13
5 4 14
5 1 5
;
run;

%fit(by34-rev-c1e-06-m20,1e-06,20);
%fit(by34-rev-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 -2 9
3 -2 7
3 1 10
5 1 13
5 4 14
7 4 5
;
run;

%fit(by43-c1e-06-m20,1e-06,20);
%fit(by43-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 7 9
3 7 7
3 4 10
5 4 13
5 1 14
7 1 5
;
run;

%fit(by43-rev-c1e-06-m20,1e-06,20);
%fit(by43-rev-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 -2 9
3 -2 7
3 1 10
5 1 13
5 4 14
7 4 5
7 7 11
;
run;

%fit(control4-c1e-06-m20,1e-06,20);
%fit(control4-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 10 9
3 10 7
3 7 10
5 7 13
5 4 14
7 4 5
7 1 11
;
run;

%fit(control4-rev-c1e-06-m20,1e-06,20);
%fit(control4-rev-c1e-06-m200,1e-06,200);
data probe; input x y f; datalines;
1 -2 9
3 -2 7
3 1 10
5 1 13
5 4 14
7 4 5
7 7 11
7 10 7
;
run;

%fit(by45-c1e-06-m20,1e-06,20);
%fit(by45-c1e-06-m200,1e-06,200);
