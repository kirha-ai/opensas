data probe; input x y w; datalines;
-9.5 0 4
-3.0 0 1
-2.875 1 5
-2.625 1 2
-0.5 1 1
1.625 1 5
1.875 1 2
2.375 1 1
6.625 1 5
8.875 1 5
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(perturb-3-sweep-1,1,1,0.000858272030785402,200);
%fit(perturb-3-sweep-2,1,1,0.00114436270771387,200);
%fit(perturb-3-sweep-3,1,1,0.0012874080461781,200);
%fit(perturb-3-sweep-4,1,1,0.00135893071541022,200);
%fit(perturb-3-sweep-5,1,1,0.00140184431694949,200);
%fit(perturb-3-sweep-6,1,1,0.00141614885079591,200);
%fit(perturb-3-sweep-7,1,1,0.0014290229312577,200);
%fit(perturb-3-sweep-8,1,1,0.00143045338464234,200);
%fit(perturb-3-sweep-9,1,1,0.00143188383802698,200);
%fit(perturb-3-sweep-10,1,1,0.00144475791848876,200);
%fit(perturb-3-sweep-11,1,1,0.00145906245233518,200);
%fit(perturb-3-sweep-12,1,1,0.00150197605387445,200);
%fit(perturb-3-sweep-13,1,1,0.00157349872310657,200);
%fit(perturb-3-sweep-14,1,1,0.0017165440615708,200);
%fit(perturb-3-sweep-15,1,1,0.00214568007696351,200);
%fit(perturb-3-first-m14,1,1,0.00214568007696,14);
%fit(perturb-3-first-m15,1,1,0.00214568007696,15);
%fit(perturb-3-first-step,1,1,0.999,1);
