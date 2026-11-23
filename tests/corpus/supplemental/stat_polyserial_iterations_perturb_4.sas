data probe; input x y w; datalines;
-9.5 0 4
-3.0 0 2
-2.875 1 5
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
%fit(perturb-4-sweep-1,1,1,0.000553326986276811,200);
%fit(perturb-4-sweep-2,1,1,0.000737769315035748,200);
%fit(perturb-4-sweep-3,1,1,0.000829990479415217,200);
%fit(perturb-4-sweep-4,1,1,0.000876101061604951,200);
%fit(perturb-4-sweep-5,1,1,0.000903767410918791,200);
%fit(perturb-4-sweep-6,1,1,0.000912989527356738,200);
%fit(perturb-4-sweep-7,1,1,0.00092128943215089,200);
%fit(perturb-4-sweep-8,1,1,0.000922211643794685,200);
%fit(perturb-4-sweep-9,1,1,0.00092313385543848,200);
%fit(perturb-4-sweep-10,1,1,0.000931433760232632,200);
%fit(perturb-4-sweep-11,1,1,0.000940655876670579,200);
%fit(perturb-4-sweep-12,1,1,0.000968322225984419,200);
%fit(perturb-4-sweep-13,1,1,0.00101443280817415,200);
%fit(perturb-4-sweep-14,1,1,0.00110665397255362,200);
%fit(perturb-4-sweep-15,1,1,0.00138331746569203,200);
%fit(perturb-4-first-m12,1,1,0.000553326986277,12);
%fit(perturb-4-first-m13,1,1,0.000553326986277,13);
%fit(perturb-4-first-step,1,1,0.999,1);
