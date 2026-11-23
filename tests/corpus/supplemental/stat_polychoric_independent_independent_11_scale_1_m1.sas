%macro fit(id,converge,iter);
ods output PolychoricCorr=fit;
proc corr data=probe polychoric(converge=&converge maxiter=&iter);
var x; with y; freq f; run;
data _null_; set fit; file print;
put  "CORRFIT &id " NObs best32. " " Corr best32. " " StdErr best32. " " WaldChiSq best32. " " LRChiSq best32.; run;
%mend;
data probe; input x y f; datalines;
0 0 3690
0 1 3180
1 0 3198
1 1 2756
;
run;

%fit(independent-11-scale-1-m1,0.99,1);
data probe; input x y f; datalines;
0 0 9280
0 1 2088
1 0 3280
1 1 738
;
run;

%fit(independent-12-scale-1-m1,0.99,1);
