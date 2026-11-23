data probe; input x y w; datalines;
-1.79 0 1
3.42 1 4
0.302 0 2
4.055 2 1
3.664 2 2
-3.304 1 2
-3.423 0 3
0.041 2 4
-0.828 0 1
0.969 1 3
1.735 1 3
1.502 2 4
3.406 2 2
3.03 1 1
-4.243 2 3
2.867 2 1
-1.347 0 1
-4.593 0 4
2.475 1 3
1.655 2 2
0.898 1 3
1.319 0 2
2.617 1 1
1.532 1 4
-2.368 0 1
1.113 1 1
-0.422 1 2
-0.364 0 2
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(blind-g5_1_u_2,1,1,0.0001,2);
%fit(blind-g5_1_u_3,1,1,0.0001,3);
%fit(blind-g5_1_u_4,1,1,0.0001,4);
%fit(blind-g5_1_u_200,1,1,0.0001,200);
%fit(blind-g5_1_v_2,1,1,1e-10,2);
%fit(blind-g5_1_v_3,1,1,1e-10,3);
%fit(blind-g5_1_v_4,1,1,1e-10,4);
%fit(blind-g5_1_v_200,1,1,1e-10,200);
