data probe; input x y w; datalines;
2.922 2 1
2.384 1 5
1.311 2 6
-2.339 0 3
-5.051 0 5
2.265 1 6
2.379 2 4
1.56 1 3
-1.849 1 4
-4.085 1 6
-3.055 0 1
0.966 2 4
5.113 0 5
-1.936 0 3
-0.115 2 6
-1.376 2 5
-3.766 0 5
-3.534 1 3
-1.965 1 5
0.096 2 2
-2.829 0 6
2.367 2 6
3.958 2 5
3.309 2 6
-0.185 1 6
3.066 2 1
-2.32 0 6
-7.092 0 4
-0.375 0 2
-1.497 0 5
1.269 2 3
1.662 0 1
1.683 2 1
1.124 2 2
-1.84 0 4
0.645 1 6
-0.102 1 6
1.811 1 2
3.119 2 5
0.406 1 4
2.854 1 1
-6.702 0 2
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(affine-t3_x_4,1,1,1e-10,4);
%fit(affine-t3_x_200,1,1,1e-10,200);
%fit(affine-t3_xt_4,1048576,1,1e-10,4);
%fit(affine-t3_xt_200,1048576,1,1e-10,200);
%fit(affine-t3_xs_4,9.5367431640625e-07,1,1e-10,4);
%fit(affine-t3_xs_200,9.5367431640625e-07,1,1e-10,200);
