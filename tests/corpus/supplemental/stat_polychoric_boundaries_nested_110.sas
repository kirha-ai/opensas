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

%fit(nested-110,3.7e-06,4);
%fit(nested-111,3.7e-06,5);
%fit(nested-112,3.7e-06,6);
%fit(nested-113,3.7e-06,7);
%fit(nested-114,3.7e-06,8);
%fit(nested-115,3.7e-06,9);
%fit(nested-116,3.7e-06,10);
%fit(nested-117,3.7e-06,12);
%fit(nested-118,3.7e-06,200);
%fit(nested-119,3.7e-07,1);
%fit(nested-120,3.7e-07,2);
%fit(nested-121,3.7e-07,3);
%fit(nested-122,3.7e-07,4);
%fit(nested-123,3.7e-07,5);
%fit(nested-124,3.7e-07,6);
%fit(nested-125,3.7e-07,7);
%fit(nested-126,3.7e-07,8);
%fit(nested-127,3.7e-07,9);
