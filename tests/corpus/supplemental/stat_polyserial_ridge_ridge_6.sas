data probe; input x y w; datalines;
-9.5 0 4
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
%fit(ridge-6-c0.999-m1,1,1,0.999,1);
%fit(ridge-6-c0.2-m2,1,1,0.2,2);
%fit(ridge-6-c0.1-m2,1,1,0.1,2);
%fit(ridge-6-c0.05-m3,1,1,0.05,3);
%fit(ridge-6-c0.01-m200,1,1,0.01,200);
%fit(ridge-6-c0.02-m200,1,1,0.02,200);
%fit(ridge-6-c0.015-m200,1,1,0.015,200);
%fit(ridge-6-c0.012-m200,1,1,0.012,200);
%fit(ridge-6-c0.0101-m200,1,1,0.0101,200);
%fit(ridge-6-c0.01-m4,1,1,0.01,4);
%fit(ridge-6-c0.01-m5,1,1,0.01,5);
%fit(ridge-6-c0.01-m6,1,1,0.01,6);
%fit(ridge-6-c0.01-m7,1,1,0.01,7);
%fit(ridge-6-c0.01-m8,1,1,0.01,8);
%fit(ridge-6-c0.01-m9,1,1,0.01,9);
%fit(ridge-6-c0.01-m20,1,1,0.01,20);
%fit(ridge-6-c0.0099-m200,1,1,0.0099,200);
%fit(ridge-6-c0.008-m200,1,1,0.008,200);
%fit(ridge-6-c0.006-m200,1,1,0.006,200);
%fit(ridge-6-c0.004-m200,1,1,0.004,200);
%fit(ridge-6-c0.002-m200,1,1,0.002,200);
%fit(ridge-6-c0.001-m200,1,1,0.001,200);
