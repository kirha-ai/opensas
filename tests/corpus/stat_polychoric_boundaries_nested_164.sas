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

%fit(nested-164,0.00037,10);
%fit(nested-165,0.00037,12);
%fit(nested-166,0.00037,200);
%fit(nested-167,3.7e-05,1);
%fit(nested-168,3.7e-05,2);
%fit(nested-169,3.7e-05,3);
%fit(nested-170,3.7e-05,4);
%fit(nested-171,3.7e-05,5);
%fit(nested-172,3.7e-05,6);
%fit(nested-173,3.7e-05,7);
%fit(nested-174,3.7e-05,8);
%fit(nested-175,3.7e-05,9);
%fit(nested-176,3.7e-05,10);
%fit(nested-177,3.7e-05,12);
%fit(nested-178,3.7e-05,200);
%fit(nested-179,3.7e-06,1);
%fit(nested-180,3.7e-06,2);
%fit(nested-181,3.7e-06,3);
