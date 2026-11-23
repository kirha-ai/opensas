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
%fit(final-blind-c8_0_1,1,1,0.3,1);
%fit(final-blind-c8_0_2,1,1,0.3,2);
%fit(final-blind-c8_0_3,1,1,0.3,3);
%fit(final-blind-c8_0_4,1,1,0.3,4);
%fit(final-blind-c8_0_5,1,1,0.3,5);
%fit(final-blind-c8_0_200,1,1,0.3,200);
%fit(final-blind-c8_1_1,1,1,0.1,1);
%fit(final-blind-c8_1_2,1,1,0.1,2);
%fit(final-blind-c8_1_3,1,1,0.1,3);
%fit(final-blind-c8_1_4,1,1,0.1,4);
%fit(final-blind-c8_1_5,1,1,0.1,5);
%fit(final-blind-c8_1_200,1,1,0.1,200);
%fit(final-blind-c8_2_1,1,1,0.03,1);
%fit(final-blind-c8_2_2,1,1,0.03,2);
%fit(final-blind-c8_2_3,1,1,0.03,3);
%fit(final-blind-c8_2_4,1,1,0.03,4);
%fit(final-blind-c8_2_5,1,1,0.03,5);
%fit(final-blind-c8_2_200,1,1,0.03,200);
%fit(final-blind-c8_3_1,1,1,0.01,1);
%fit(final-blind-c8_3_2,1,1,0.01,2);
%fit(final-blind-c8_3_3,1,1,0.01,3);
%fit(final-blind-c8_3_4,1,1,0.01,4);
%fit(final-blind-c8_3_5,1,1,0.01,5);
%fit(final-blind-c8_3_200,1,1,0.01,200);
%fit(final-blind-c8_4_1,1,1,0.003,1);
%fit(final-blind-c8_4_2,1,1,0.003,2);
%fit(final-blind-c8_4_3,1,1,0.003,3);
%fit(final-blind-c8_4_4,1,1,0.003,4);
%fit(final-blind-c8_4_5,1,1,0.003,5);
%fit(final-blind-c8_4_200,1,1,0.003,200);
%fit(final-blind-c8_5_1,1,1,0.0001,1);
%fit(final-blind-c8_5_2,1,1,0.0001,2);
%fit(final-blind-c8_5_3,1,1,0.0001,3);
%fit(final-blind-c8_5_4,1,1,0.0001,4);
%fit(final-blind-c8_5_5,1,1,0.0001,5);
%fit(final-blind-c8_5_200,1,1,0.0001,200);
%fit(final-blind-c8_6_1,1,1,1e-10,1);
%fit(final-blind-c8_6_2,1,1,1e-10,2);
%fit(final-blind-c8_6_3,1,1,1e-10,3);
%fit(final-blind-c8_6_4,1,1,1e-10,4);
%fit(final-blind-c8_6_5,1,1,1e-10,5);
%fit(final-blind-c8_6_200,1,1,1e-10,200);
