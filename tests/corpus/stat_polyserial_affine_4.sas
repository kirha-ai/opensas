data probe; input x y w; datalines;
-1.699 0 1
3.177 2 1
-1.437 1 5
-0.216 2 4
6.056 1 4
3.596 2 3
1.577 1 2
-6.034 0 5
3.635 2 2
-2.391 0 1
-0.065 2 1
1.288 2 6
-0.425 1 2
2.199 1 4
-2.077 0 2
0.65 1 6
2.285 2 3
2.275 2 5
4.241 2 6
-1.212 1 2
-0.587 2 1
-2.21 2 1
6.12 2 4
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(affine-t4_x_4,1,1,1e-10,4);
%fit(affine-t4_x_200,1,1,1e-10,200);
%fit(affine-t4_xt_4,1048576,1,1e-10,4);
%fit(affine-t4_xt_200,1048576,1,1e-10,200);
%fit(affine-t4_xs_4,9.5367431640625e-07,1,1e-10,4);
%fit(affine-t4_xs_200,9.5367431640625e-07,1,1e-10,200);
