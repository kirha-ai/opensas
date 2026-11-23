data probe; input x y w; datalines;
3.868 2 1
2.821 0 1
-1.913 3 1
1.678 0 2
-1.087 3 3
-1.333 1 5
-0.762 3 1
-1.364 3 1
1.557 3 2
-2.226 1 3
-1.231 3 3
-0.84 0 5
0.424 3 4
-0.281 2 2
-0.429 3 3
-0.056 3 3
0.579 0 2
-0.174 0 2
0.579 1 1
1.213 1 1
-5.806 1 2
1.873 0 2
4.277 1 3
-0.33 1 4
0.119 3 1
-2.377 1 5
-2.563 3 2
-1.386 2 1
1.985 3 4
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(final-blind-c5_0_2,1,1,0.0001,2);
%fit(final-blind-c5_0_3,1,1,0.0001,3);
%fit(final-blind-c5_0_200,1,1,0.0001,200);
%fit(final-blind-c5_1_2,1,1,1e-10,2);
%fit(final-blind-c5_1_3,1,1,1e-10,3);
%fit(final-blind-c5_1_200,1,1,1e-10,200);
%fit(final-blind-c5_2_2,1024,1,1e-10,2);
%fit(final-blind-c5_2_3,1024,1,1e-10,3);
%fit(final-blind-c5_2_200,1024,1,1e-10,200);
