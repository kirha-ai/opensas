data probe; input x y w; datalines;
0.38 1 5
-1.243 1 5
-1.849 0 5
-1.208 0 1
0.574 0 1
-1.27 0 5
-0.26 1 4
-2.128 0 2
0.693 1 2
3.18 1 2
-1.901 0 3
1.051 1 4
-0.249 0 2
1.076 0 1
-1.456 0 4
-0.812 1 1
-0.277 1 5
-3.024 0 3
1.465 1 3
3.19 1 1
-1.141 0 3
-3.119 0 3
1.807 0 1
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(final-blind-c3_0_2,1,1,0.0001,2);
%fit(final-blind-c3_0_3,1,1,0.0001,3);
%fit(final-blind-c3_0_200,1,1,0.0001,200);
%fit(final-blind-c3_1_2,1,1,1e-10,2);
%fit(final-blind-c3_1_3,1,1,1e-10,3);
%fit(final-blind-c3_1_200,1,1,1e-10,200);
%fit(final-blind-c3_2_2,1024,1,1e-10,2);
%fit(final-blind-c3_2_3,1024,1,1e-10,3);
%fit(final-blind-c3_2_200,1024,1,1e-10,200);
