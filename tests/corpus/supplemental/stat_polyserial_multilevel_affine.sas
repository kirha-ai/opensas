data probe; input x y w; datalines;
0 0 2
1 1 3
2 2 4
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(affine-c0.0001-m1,1,1,0.0001,1);
%fit(affine-c0.0001-m5,1,1,0.0001,5);
%fit(affine-c0.0001-m200,1,1,0.0001,200);
%fit(affine-c0.5-m1,1,1,0.5,1);
%fit(affine-c0.01-m1,1,1,0.01,1);
%fit(affine-c0.01-m5,1,1,0.01,5);
%fit(affine-c0.01-m200,1,1,0.01,200);
