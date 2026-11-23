data probe; input x y w; datalines;
-9.5 0 4
-3.0 0 1
-2.875 1 5
-2.625 1 2
-0.5 1 1
1.375 1 5
1.875 1 2
2.375 1 1
6.625 1 5
8.875 1 2
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(perturb-6-sweep-1,1,1,0.00117794617435787,200);
%fit(perturb-6-sweep-2,1,1,0.00157059489914383,200);
%fit(perturb-6-sweep-3,1,1,0.00176691926153681,200);
%fit(perturb-6-sweep-4,1,1,0.0018650814427333,200);
%fit(perturb-6-sweep-5,1,1,0.00192397875145119,200);
%fit(perturb-6-sweep-6,1,1,0.00194361118769049,200);
%fit(perturb-6-sweep-7,1,1,0.00196128038030586,200);
%fit(perturb-6-sweep-8,1,1,0.00196324362392979,200);
%fit(perturb-6-sweep-9,1,1,0.00196520686755372,200);
%fit(perturb-6-sweep-10,1,1,0.00198287606016909,200);
%fit(perturb-6-sweep-11,1,1,0.00200250849640838,200);
%fit(perturb-6-sweep-12,1,1,0.00206140580512628,200);
%fit(perturb-6-sweep-13,1,1,0.00215956798632277,200);
%fit(perturb-6-sweep-14,1,1,0.00235589234871575,200);
%fit(perturb-6-sweep-15,1,1,0.00294486543589468,200);
%fit(perturb-6-first-m16,1,1,0.00176691926154,16);
%fit(perturb-6-first-m17,1,1,0.00176691926154,17);
%fit(perturb-6-first-step,1,1,0.999,1);
