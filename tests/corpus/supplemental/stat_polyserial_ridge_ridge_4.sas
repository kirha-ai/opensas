data probe; input x y w; datalines;
-6.125 0 3
-1.75 0 4
0.5 0 3
2.25 0 3
4.125 0 1
5.25 0 3
7.5 1 1
7.875 0 3
10.375 1 2
13.625 1 3
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(ridge-4-c0.999-m1,1,1,0.999,1);
%fit(ridge-4-c0.2-m2,1,1,0.2,2);
%fit(ridge-4-c0.1-m2,1,1,0.1,2);
%fit(ridge-4-c0.05-m3,1,1,0.05,3);
%fit(ridge-4-c0.01-m200,1,1,0.01,200);
