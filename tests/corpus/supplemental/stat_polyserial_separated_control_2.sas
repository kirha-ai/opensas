data probe; input x y w; datalines;
128.0 0 1
120.0 0 2
88.0 0 2
72.0 0 1
56.0 1 3
40.0 1 2
24.0 1 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(separated-control-2-e.01m2,1,1,0.01,2);
%fit(separated-control-2-e.01m8,1,1,0.01,8);
%fit(separated-control-2-e.0001m2,1,1,0.0001,2);
%fit(separated-control-2-e.0001m8,1,1,0.0001,8);
