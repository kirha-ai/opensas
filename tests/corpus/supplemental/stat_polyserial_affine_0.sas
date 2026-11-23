data probe; input x y w; datalines;
-0.542 0 6
-0.018 0 6
0.339 1 3
-3.665 1 4
-3.372 0 1
5.551 2 1
-2.467 1 3
-2.578 0 6
-4.32 0 4
1.538 2 5
-2.828 0 4
4.928 2 6
-2.589 0 4
1.912 2 1
2.65 1 1
0.417 1 6
-3.447 0 4
3.131 2 4
-4.464 1 5
4.32 2 1
-2.655 0 4
2.371 1 4
1.685 1 1
-0.258 1 3
3.148 2 1
-1.365 1 2
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(affine-t0_x_4,1,1,1e-10,4);
%fit(affine-t0_x_200,1,1,1e-10,200);
%fit(affine-t0_xt_4,1048576,1,1e-10,4);
%fit(affine-t0_xt_200,1048576,1,1e-10,200);
%fit(affine-t0_xs_4,9.5367431640625e-07,1,1e-10,4);
%fit(affine-t0_xs_200,9.5367431640625e-07,1,1e-10,200);
