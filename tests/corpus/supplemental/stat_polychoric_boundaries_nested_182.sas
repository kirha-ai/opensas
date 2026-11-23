%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 9
0 -1 0
2 0 13
2 -1 0
7 0 0
7 -1 21
;
run;

%fit(nested-182,3.7e-06,4);
%fit(nested-183,3.7e-06,5);
%fit(nested-184,3.7e-06,6);
%fit(nested-185,3.7e-06,7);
%fit(nested-186,3.7e-06,8);
%fit(nested-187,3.7e-06,9);
%fit(nested-188,3.7e-06,10);
%fit(nested-189,3.7e-06,12);
%fit(nested-190,3.7e-06,200);
%fit(nested-191,3.7e-07,1);
%fit(nested-192,3.7e-07,2);
%fit(nested-193,3.7e-07,3);
%fit(nested-194,3.7e-07,4);
%fit(nested-195,3.7e-07,5);
%fit(nested-196,3.7e-07,6);
%fit(nested-197,3.7e-07,7);
%fit(nested-198,3.7e-07,8);
%fit(nested-199,3.7e-07,9);
