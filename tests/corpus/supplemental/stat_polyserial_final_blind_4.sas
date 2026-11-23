data probe; input x y w; datalines;
-1.842 2 4
0.029 0 4
-1.53 0 5
-1.006 2 5
2.033 1 1
1.828 0 2
2.547 0 4
0.312 2 5
-1.666 2 4
-1.038 1 3
-0.271 0 4
0.349 0 3
-2.404 2 3
1.546 1 2
3.081 0 5
-1.872 0 1
-2.924 2 2
-0.127 2 4
-0.058 0 1
0.976 0 3
-2.57 2 3
-0.018 2 4
-1.973 2 5
0.389 1 4
0.737 1 3
0.942 0 4
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(final-blind-c4_0_2,1,1,0.0001,2);
%fit(final-blind-c4_0_3,1,1,0.0001,3);
%fit(final-blind-c4_0_200,1,1,0.0001,200);
%fit(final-blind-c4_1_2,1,1,1e-10,2);
%fit(final-blind-c4_1_3,1,1,1e-10,3);
%fit(final-blind-c4_1_200,1,1,1e-10,200);
%fit(final-blind-c4_2_2,1024,1,1e-10,2);
%fit(final-blind-c4_2_3,1024,1,1e-10,3);
%fit(final-blind-c4_2_200,1024,1,1e-10,200);
