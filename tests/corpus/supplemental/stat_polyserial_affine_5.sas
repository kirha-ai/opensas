data probe; input x y w; datalines;
-1.864 1 2
-1.201 2 3
3.221 2 1
-2.663 0 1
-3.367 1 5
-1.276 1 3
-2.278 1 5
1.647 2 2
-0.097 0 6
0.827 1 1
-1.569 0 5
2.084 2 3
2.494 2 6
-3.254 1 2
1.793 2 5
4.1 2 6
-2.451 1 2
3.654 2 6
-4.626 0 1
2.298 0 4
-5.211 0 2
-0.167 2 4
0.604 1 5
-0.102 2 3
3.768 1 2
0.363 1 3
1.467 1 2
-0.731 1 4
0.112 1 3
-2.374 0 4
-1.762 1 5
1.133 2 1
-0.44 2 5
0.086 2 4
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(affine-t5_x_4,1,1,1e-10,4);
%fit(affine-t5_x_200,1,1,1e-10,200);
%fit(affine-t5_xt_4,1048576,1,1e-10,4);
%fit(affine-t5_xt_200,1048576,1,1e-10,200);
%fit(affine-t5_xs_4,9.5367431640625e-07,1,1e-10,4);
%fit(affine-t5_xs_200,9.5367431640625e-07,1,1e-10,200);
