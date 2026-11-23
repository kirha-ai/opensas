data probe; input x y w; datalines;
-9.625 1 1
-8.75 1 3
-7.75 1 3
-5.375 1 1
-2.875 1 2
-1.375 1 5
0.5 1 4
4.25 0 3
6.25 1 1
9.125 0 1
9.625 0 5
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(ridge-1-c0.999-m1,1,1,0.999,1);
%fit(ridge-1-c0.2-m2,1,1,0.2,2);
%fit(ridge-1-c0.1-m2,1,1,0.1,2);
%fit(ridge-1-c0.05-m3,1,1,0.05,3);
%fit(ridge-1-c0.01-m200,1,1,0.01,200);
