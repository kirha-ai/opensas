data probe; input x y w; datalines;
5.313 2 6
1.299 1 2
-2.954 0 2
-0.007 1 4
4.304 2 1
-2.244 0 5
-8.164 0 6
-0.386 2 4
4.652 2 1
-4.384 0 3
0.808 0 4
-1.505 0 4
3.489 0 6
-3.459 2 6
-0.32 1 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(affine-t6_x_4,1,1,1e-10,4);
%fit(affine-t6_x_200,1,1,1e-10,200);
%fit(affine-t6_xt_4,1048576,1,1e-10,4);
%fit(affine-t6_xt_200,1048576,1,1e-10,200);
%fit(affine-t6_xs_4,9.5367431640625e-07,1,1e-10,4);
%fit(affine-t6_xs_200,9.5367431640625e-07,1,1e-10,200);
