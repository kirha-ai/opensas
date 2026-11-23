data probe; input x y w; datalines;
2.709 2 2
0.645 0 6
0.071 2 6
-2.242 1 3
1.11 2 6
-3.794 2 4
-2.721 0 1
4.557 2 5
2.305 1 2
1.628 1 4
2.422 1 4
-2.704 0 4
2.47 2 2
-1.596 1 6
5.396 2 3
1.541 1 5
-2.129 0 2
-4.24 0 6
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(affine-t1_x_4,1,1,1e-10,4);
%fit(affine-t1_x_200,1,1,1e-10,200);
%fit(affine-t1_xt_4,1048576,1,1e-10,4);
%fit(affine-t1_xt_200,1048576,1,1e-10,200);
%fit(affine-t1_xs_4,9.5367431640625e-07,1,1e-10,4);
%fit(affine-t1_xs_200,9.5367431640625e-07,1,1e-10,200);
