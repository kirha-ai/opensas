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

%fit(nested-92,0.00037,10);
%fit(nested-93,0.00037,12);
%fit(nested-94,0.00037,200);
%fit(nested-95,3.7e-05,1);
%fit(nested-96,3.7e-05,2);
%fit(nested-97,3.7e-05,3);
%fit(nested-98,3.7e-05,4);
%fit(nested-99,3.7e-05,5);
%fit(nested-100,3.7e-05,6);
%fit(nested-101,3.7e-05,7);
%fit(nested-102,3.7e-05,8);
%fit(nested-103,3.7e-05,9);
%fit(nested-104,3.7e-05,10);
%fit(nested-105,3.7e-05,12);
%fit(nested-106,3.7e-05,200);
%fit(nested-107,3.7e-06,1);
%fit(nested-108,3.7e-06,2);
%fit(nested-109,3.7e-06,3);
