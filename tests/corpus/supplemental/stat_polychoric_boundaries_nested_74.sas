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

%fit(nested-74,0.0037,4);
%fit(nested-75,0.0037,5);
%fit(nested-76,0.0037,6);
%fit(nested-77,0.0037,7);
%fit(nested-78,0.0037,8);
%fit(nested-79,0.0037,9);
%fit(nested-80,0.0037,10);
%fit(nested-81,0.0037,12);
%fit(nested-82,0.0037,200);
%fit(nested-83,0.00037,1);
%fit(nested-84,0.00037,2);
%fit(nested-85,0.00037,3);
%fit(nested-86,0.00037,4);
%fit(nested-87,0.00037,5);
%fit(nested-88,0.00037,6);
%fit(nested-89,0.00037,7);
%fit(nested-90,0.00037,8);
%fit(nested-91,0.00037,9);
