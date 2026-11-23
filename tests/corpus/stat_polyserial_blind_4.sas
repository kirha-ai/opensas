data probe; input x y w; datalines;
2.614 2 1
-0.088 0 4
3.099 2 3
-3.292 0 3
0.017 0 3
3.743 2 3
-0.25 1 4
0.839 1 1
-2.012 2 2
-0.001 0 4
-1.564 1 4
-2.21 2 1
5.939 2 3
3.834 2 2
-0.103 0 2
-2.986 0 4
2.297 2 1
1.32 0 3
-2.932 0 3
-1.453 1 3
-1.404 0 1
0.556 1 1
-0.941 1 1
-3.293 0 1
5.826 1 2
-1.823 1 1
-1.029 1 1
0.021 1 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(blind-g4_1_u_2,1,1,0.0001,2);
%fit(blind-g4_1_u_3,1,1,0.0001,3);
%fit(blind-g4_1_u_4,1,1,0.0001,4);
%fit(blind-g4_1_u_200,1,1,0.0001,200);
%fit(blind-g4_1_v_2,1,1,1e-10,2);
%fit(blind-g4_1_v_3,1,1,1e-10,3);
%fit(blind-g4_1_v_4,1,1,1e-10,4);
%fit(blind-g4_1_v_200,1,1,1e-10,200);
