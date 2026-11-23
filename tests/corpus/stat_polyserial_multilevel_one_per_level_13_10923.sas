data probe; input x y w; datalines;
0 0 2
1 1 3
13.10923 2 4
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(one-per-level-13.10923-c0.1-m200,1,1,0.1,200);
