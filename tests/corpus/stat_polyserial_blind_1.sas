data probe; input x y w; datalines;
-1.057 2 2
-2.297 0 4
-3.325 0 4
0.819 1 1
1.542 1 2
3.347 2 1
0.05 1 4
0.831 2 1
-0.124 0 4
5.299 2 4
-2.413 2 2
-6.191 0 1
-2.009 0 3
0.168 1 1
-1.606 0 2
2.618 2 1
-0.268 1 1
-0.85 2 3
4.663 2 3
2.655 0 4
2.819 0 4
2.811 1 1
-1.184 0 4
-1.832 0 3
-1.786 1 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(blind-g1_1_u_2,1,1,0.0001,2);
%fit(blind-g1_1_u_3,1,1,0.0001,3);
%fit(blind-g1_1_u_4,1,1,0.0001,4);
%fit(blind-g1_1_u_200,1,1,0.0001,200);
%fit(blind-g1_1_v_2,1,1,1e-10,2);
%fit(blind-g1_1_v_3,1,1,1e-10,3);
%fit(blind-g1_1_v_4,1,1,1e-10,4);
%fit(blind-g1_1_v_200,1,1,1e-10,200);
%fit(blind-g1_10_u_2,1,10,0.0001,2);
%fit(blind-g1_10_u_3,1,10,0.0001,3);
%fit(blind-g1_10_u_4,1,10,0.0001,4);
%fit(blind-g1_10_u_200,1,10,0.0001,200);
%fit(blind-g1_10_v_2,1,10,1e-10,2);
%fit(blind-g1_10_v_3,1,10,1e-10,3);
%fit(blind-g1_10_v_4,1,10,1e-10,4);
%fit(blind-g1_10_v_200,1,10,1e-10,200);
