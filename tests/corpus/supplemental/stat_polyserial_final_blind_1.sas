data probe; input x y w; datalines;
-3.411 2 4
0.65 0 3
2.013 0 5
0.303 0 1
-0.479 2 1
4.113 1 2
2.021 0 1
1.199 1 5
-1.141 2 3
-1.656 0 3
-0.462 2 5
-1.553 2 4
3.109 0 5
1.137 0 2
-0.464 0 3
-2.939 1 4
-2.027 0 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(final-blind-c1_0_2,1,1,0.0001,2);
%fit(final-blind-c1_0_3,1,1,0.0001,3);
%fit(final-blind-c1_0_200,1,1,0.0001,200);
%fit(final-blind-c1_1_2,1,1,1e-10,2);
%fit(final-blind-c1_1_3,1,1,1e-10,3);
%fit(final-blind-c1_1_200,1,1,1e-10,200);
%fit(final-blind-c1_2_2,1024,1,1e-10,2);
%fit(final-blind-c1_2_3,1024,1,1e-10,3);
%fit(final-blind-c1_2_200,1024,1,1e-10,200);
