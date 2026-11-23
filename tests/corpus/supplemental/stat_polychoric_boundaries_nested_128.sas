%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 7
0 1 11
0 3 0
1 0 0
1 1 0
1 3 17
;
run;

%fit(nested-128,3.7e-07,10);
%fit(nested-129,3.7e-07,12);
%fit(nested-130,3.7e-07,200);
data probe; input x y f; datalines;
0 0 9
0 -1 0
2 0 13
2 -1 0
7 0 0
7 -1 21
;
run;

%fit(nested-131,0.99,1);
%fit(nested-132,0.99,2);
%fit(nested-133,0.99,3);
%fit(nested-134,0.99,4);
%fit(nested-135,0.99,5);
%fit(nested-136,0.99,6);
%fit(nested-137,0.99,7);
%fit(nested-138,0.99,8);
%fit(nested-139,0.99,9);
%fit(nested-140,0.99,10);
%fit(nested-141,0.99,12);
%fit(nested-142,0.99,200);
%fit(nested-143,0.0037,1);
%fit(nested-144,0.0037,2);
%fit(nested-145,0.0037,3);
