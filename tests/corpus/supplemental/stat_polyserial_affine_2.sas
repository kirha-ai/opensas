data probe; input x y w; datalines;
2.612 2 4
-3.36 1 6
-1.262 1 5
-3.008 1 6
1.25 1 1
-0.568 0 1
1.829 2 3
1.45 1 5
-4.449 0 4
-1.326 1 3
-0.953 1 1
1.687 2 6
0.484 1 5
1.668 2 1
-3.812 1 6
-1.221 0 4
4.922 2 5
1.8 1 2
2.963 2 3
2.91 2 1
0.799 2 6
1.977 1 1
1.76 2 1
4.85 2 6
-1.913 1 6
5.31 2 5
-1.538 2 1
-1.137 1 2
0.921 2 2
-1.94 0 2
3.764 2 2
-3.78 0 2
-0.956 2 1
2.754 2 5
-1.512 0 6
3.864 2 3
4.187 2 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(affine-t2_x_4,1,1,1e-10,4);
%fit(affine-t2_x_200,1,1,1e-10,200);
%fit(affine-t2_xt_4,1048576,1,1e-10,4);
%fit(affine-t2_xt_200,1048576,1,1e-10,200);
%fit(affine-t2_xs_4,9.5367431640625e-07,1,1e-10,4);
%fit(affine-t2_xs_200,9.5367431640625e-07,1,1e-10,200);
