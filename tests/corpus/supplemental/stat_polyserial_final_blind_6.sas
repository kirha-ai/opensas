data probe; input x y w; datalines;
3.097 0 5
1.642 1 2
0.64 1 1
0.543 1 4
2.851 1 4
2.408 1 2
0.642 0 4
1.847 0 5
2.554 0 4
-2.594 0 2
-0.813 1 5
-1.564 0 2
-1.654 1 2
0.175 1 2
0.786 1 1
-1.717 1 3
-1.816 1 4
3.249 1 3
0.027 1 3
-2.577 1 1
-1.085 1 4
0.127 0 4
0.222 0 5
1.697 1 5
0.546 0 1
3.068 0 3
-0.666 1 5
1.932 1 3
-1.249 0 5
-2.51 0 3
-1.079 0 1
0.236 1 2
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(final-blind-c6_0_2,1,1,0.0001,2);
%fit(final-blind-c6_0_3,1,1,0.0001,3);
%fit(final-blind-c6_0_200,1,1,0.0001,200);
%fit(final-blind-c6_1_2,1,1,1e-10,2);
%fit(final-blind-c6_1_3,1,1,1e-10,3);
%fit(final-blind-c6_1_200,1,1,1e-10,200);
%fit(final-blind-c6_2_2,1024,1,1e-10,2);
%fit(final-blind-c6_2_3,1024,1,1e-10,3);
%fit(final-blind-c6_2_200,1024,1,1e-10,200);
