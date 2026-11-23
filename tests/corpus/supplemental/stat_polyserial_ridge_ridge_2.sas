data probe; input x y w; datalines;
-12.75 0 3
-11.75 0 4
-11.5 0 5
-10.875 1 4
-9.0 1 5
-8.125 1 2
-8.0 1 4
-6.125 1 1
-5.875 1 4
-4.625 1 1
-2.375 1 2
-2.25 1 2
-0.125 1 5
1.625 1 4
2.5 1 5
3.625 1 2
10.125 1 1
12.125 1 2
12.375 1 1
13.375 1 5
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(ridge-2-c0.999-m1,1,1,0.999,1);
%fit(ridge-2-c0.2-m2,1,1,0.2,2);
%fit(ridge-2-c0.1-m2,1,1,0.1,2);
%fit(ridge-2-c0.05-m3,1,1,0.05,3);
%fit(ridge-2-c0.01-m200,1,1,0.01,200);
