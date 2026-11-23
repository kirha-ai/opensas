data probe; input x y w; datalines;
0.884 2 1
0.743 2 3
4.267 2 4
2.287 1 3
-0.886 1 2
3.85 2 2
0.52 0 2
0.07 1 3
0.58 0 4
1.478 1 1
3.725 2 1
3.415 2 2
1.169 0 2
-1.589 1 3
-1.189 0 1
-2.089 0 3
2.259 1 2
-1.117 2 3
-2.204 1 4
0.064 1 3
3.209 2 3
-1.695 2 1
-0.738 2 2
4.595 1 1
5.141 1 1
2.722 0 2
0.357 1 3
-4.045 0 3
-2.95 1 4
1.458 2 1
3.107 1 4
-0.284 2 4
-2.775 1 1
3.688 2 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(blind-g3_1_u_2,1,1,0.0001,2);
%fit(blind-g3_1_u_3,1,1,0.0001,3);
%fit(blind-g3_1_u_4,1,1,0.0001,4);
%fit(blind-g3_1_u_200,1,1,0.0001,200);
%fit(blind-g3_1_v_2,1,1,1e-10,2);
%fit(blind-g3_1_v_3,1,1,1e-10,3);
%fit(blind-g3_1_v_4,1,1,1e-10,4);
%fit(blind-g3_1_v_200,1,1,1e-10,200);
