data probe; input x y w; datalines;
-9.5 0 4
-3.0 0 1
-2.8125 1 5
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
%fit(perturb-5-sweep-1,1,1,0.0010238630966112,200);
%fit(perturb-5-sweep-2,1,1,0.0013651507954816,200);
%fit(perturb-5-sweep-3,1,1,0.0015357946449168,200);
%fit(perturb-5-sweep-4,1,1,0.0016211165696344,200);
%fit(perturb-5-sweep-5,1,1,0.00167230972446496,200);
%fit(perturb-5-sweep-6,1,1,0.00168937410940848,200);
%fit(perturb-5-sweep-7,1,1,0.00170473205585765,200);
%fit(perturb-5-sweep-8,1,1,0.001706438494352,200);
%fit(perturb-5-sweep-9,1,1,0.00170814493284635,200);
%fit(perturb-5-sweep-10,1,1,0.00172350287929552,200);
%fit(perturb-5-sweep-11,1,1,0.00174056726423904,200);
%fit(perturb-5-sweep-12,1,1,0.0017917604190696,200);
%fit(perturb-5-sweep-13,1,1,0.0018770823437872,200);
%fit(perturb-5-sweep-14,1,1,0.0020477261932224,200);
%fit(perturb-5-sweep-15,1,1,0.002559657741528,200);
%fit(perturb-5-first-m15,1,1,0.00136515079548,15);
%fit(perturb-5-first-m16,1,1,0.00136515079548,16);
%fit(perturb-5-first-step,1,1,0.999,1);
