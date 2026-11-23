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
9.375 1 2
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(perturb-1-sweep-1,1,1,0.00113384165224364,200);
%fit(perturb-1-sweep-2,1,1,0.00151178886965818,200);
%fit(perturb-1-sweep-3,1,1,0.00170076247836546,200);
%fit(perturb-1-sweep-4,1,1,0.00179524928271909,200);
%fit(perturb-1-sweep-5,1,1,0.00185194136533127,200);
%fit(perturb-1-sweep-6,1,1,0.001870838726202,200);
%fit(perturb-1-sweep-7,1,1,0.00188784635098566,200);
%fit(perturb-1-sweep-8,1,1,0.00188973608707273,200);
%fit(perturb-1-sweep-9,1,1,0.0018916258231598,200);
%fit(perturb-1-sweep-10,1,1,0.00190863344794346,200);
%fit(perturb-1-sweep-11,1,1,0.00192753080881418,200);
%fit(perturb-1-sweep-12,1,1,0.00198422289142637,200);
%fit(perturb-1-sweep-13,1,1,0.00207870969578,200);
%fit(perturb-1-sweep-14,1,1,0.00226768330448727,200);
%fit(perturb-1-sweep-15,1,1,0.00283460413060909,200);
%fit(perturb-1-first-m16,1,1,0.00179524928272,16);
%fit(perturb-1-first-m17,1,1,0.00179524928272,17);
%fit(perturb-1-first-step,1,1,0.999,1);
