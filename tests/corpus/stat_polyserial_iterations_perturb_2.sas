data probe; input x y w; datalines;
-10.25 0 4
-3.0 0 1
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
%fit(perturb-2-sweep-1,1,1,0.0012480939791384,200);
%fit(perturb-2-sweep-2,1,1,0.00166412530551786,200);
%fit(perturb-2-sweep-3,1,1,0.0018721409687076,200);
%fit(perturb-2-sweep-4,1,1,0.00197614880030246,200);
%fit(perturb-2-sweep-5,1,1,0.00203855349925938,200);
%fit(perturb-2-sweep-6,1,1,0.00205935506557836,200);
%fit(perturb-2-sweep-7,1,1,0.00207807647526543,200);
%fit(perturb-2-sweep-8,1,1,0.00208015663189733,200);
%fit(perturb-2-sweep-9,1,1,0.00208223678852923,200);
%fit(perturb-2-sweep-10,1,1,0.0021009581982163,200);
%fit(perturb-2-sweep-11,1,1,0.00212175976453528,200);
%fit(perturb-2-sweep-12,1,1,0.0021841644634922,200);
%fit(perturb-2-sweep-13,1,1,0.00228817229508706,200);
%fit(perturb-2-sweep-14,1,1,0.0024961879582768,200);
%fit(perturb-2-sweep-15,1,1,0.003120234947846,200);
%fit(perturb-2-first-m16,1,1,0.00187214096871,16);
%fit(perturb-2-first-m17,1,1,0.00187214096871,17);
%fit(perturb-2-first-step,1,1,0.999,1);
