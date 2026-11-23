data probe; input x y w; datalines;
4.815 2 3
-0.547 1 2
2.431 2 1
-0.378 0 1
-0.604 0 1
1.13 0 2
2.575 2 2
-0.912 0 4
-0.679 2 1
-0.675 2 1
-3.44 0 2
4.263 2 4
0.79 0 1
1.287 0 3
4.853 1 3
0.049 2 4
-2.005 0 4
-2.401 0 1
-3.384 0 2
-4.175 0 3
0.543 2 2
4.101 1 3
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(blind-g0_1_u_2,1,1,0.0001,2);
%fit(blind-g0_1_u_3,1,1,0.0001,3);
%fit(blind-g0_1_u_4,1,1,0.0001,4);
%fit(blind-g0_1_u_200,1,1,0.0001,200);
%fit(blind-g0_1_v_2,1,1,1e-10,2);
%fit(blind-g0_1_v_3,1,1,1e-10,3);
%fit(blind-g0_1_v_4,1,1,1e-10,4);
%fit(blind-g0_1_v_200,1,1,1e-10,200);
%fit(blind-g0_10_u_2,1,10,0.0001,2);
%fit(blind-g0_10_u_3,1,10,0.0001,3);
%fit(blind-g0_10_u_4,1,10,0.0001,4);
%fit(blind-g0_10_u_200,1,10,0.0001,200);
%fit(blind-g0_10_v_2,1,10,1e-10,2);
%fit(blind-g0_10_v_3,1,10,1e-10,3);
%fit(blind-g0_10_v_4,1,10,1e-10,4);
%fit(blind-g0_10_v_200,1,10,1e-10,200);
