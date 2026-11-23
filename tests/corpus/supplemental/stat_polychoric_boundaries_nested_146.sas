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

%fit(nested-146,0.0037,4);
%fit(nested-147,0.0037,5);
%fit(nested-148,0.0037,6);
%fit(nested-149,0.0037,7);
%fit(nested-150,0.0037,8);
%fit(nested-151,0.0037,9);
%fit(nested-152,0.0037,10);
%fit(nested-153,0.0037,12);
%fit(nested-154,0.0037,200);
%fit(nested-155,0.00037,1);
%fit(nested-156,0.00037,2);
%fit(nested-157,0.00037,3);
%fit(nested-158,0.00037,4);
%fit(nested-159,0.00037,5);
%fit(nested-160,0.00037,6);
%fit(nested-161,0.00037,7);
%fit(nested-162,0.00037,8);
%fit(nested-163,0.00037,9);
