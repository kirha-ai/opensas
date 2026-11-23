data probe; input x y w; datalines;
-9.5 0 4
-3.0 0 1
-2.875 1 7
-2.625 1 2
-0.5 1 1
1.625 1 5
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
%fit(perturb-7-sweep-1,1,1,0.00163409813157802,200);
%fit(perturb-7-sweep-2,1,1,0.00217879750877069,200);
%fit(perturb-7-sweep-3,1,1,0.00245114719736703,200);
%fit(perturb-7-sweep-4,1,1,0.00258732204166519,200);
%fit(perturb-7-sweep-5,1,1,0.0026690269482441,200);
%fit(perturb-7-sweep-6,1,1,0.00269626191710373,200);
%fit(perturb-7-sweep-7,1,1,0.0027207733890774,200);
%fit(perturb-7-sweep-8,1,1,0.00272349688596336,200);
%fit(perturb-7-sweep-9,1,1,0.00272622038284933,200);
%fit(perturb-7-sweep-10,1,1,0.002750731854823,200);
%fit(perturb-7-sweep-11,1,1,0.00277796682368263,200);
%fit(perturb-7-sweep-12,1,1,0.00285967173026153,200);
%fit(perturb-7-sweep-13,1,1,0.0029958465745597,200);
%fit(perturb-7-sweep-14,1,1,0.00326819626315604,200);
%fit(perturb-7-sweep-15,1,1,0.00408524532894504,200);
%fit(perturb-7-first-m15,1,1,0.00408524532895,15);
%fit(perturb-7-first-m16,1,1,0.00408524532895,16);
%fit(perturb-7-first-step,1,1,0.999,1);
