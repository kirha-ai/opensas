data probe; input x y w; datalines;
-2.851 2 3
-1.424 2 3
-0.509 1 4
4.205 0 1
1.526 1 1
-1.845 1 4
0.01 0 2
3.936 2 1
-3.315 1 3
-2.994 2 3
0.908 0 2
1.568 2 1
-0.301 1 1
3.519 2 1
-2.576 0 2
4.223 2 3
0.131 0 3
-4.5 0 4
0.72 1 4
2.133 1 1
3.382 0 4
-3.414 2 4
1.013 1 3
-2.177 0 4
0.216 2 1
3.04 2 1
-1.757 1 4
0.269 1 4
1.488 0 3
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(blind-g2_1_u_2,1,1,0.0001,2);
%fit(blind-g2_1_u_3,1,1,0.0001,3);
%fit(blind-g2_1_u_4,1,1,0.0001,4);
%fit(blind-g2_1_u_200,1,1,0.0001,200);
%fit(blind-g2_1_v_2,1,1,1e-10,2);
%fit(blind-g2_1_v_3,1,1,1e-10,3);
%fit(blind-g2_1_v_4,1,1,1e-10,4);
%fit(blind-g2_1_v_200,1,1,1e-10,200);
