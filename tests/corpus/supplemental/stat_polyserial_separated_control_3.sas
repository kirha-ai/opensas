data probe; input x y w; datalines;
-4.0 0 1
-3.0 0 1
-2.0 1 1
2.0 1 1
3.0 1 1
4.0 1 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(separated-control-3-e.01m2,1,1,0.01,2);
%fit(separated-control-3-e.01m8,1,1,0.01,8);
%fit(separated-control-3-e.0001m2,1,1,0.0001,2);
%fit(separated-control-3-e.0001m8,1,1,0.0001,8);
