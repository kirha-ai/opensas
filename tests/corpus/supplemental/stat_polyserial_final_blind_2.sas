data probe; input x y w; datalines;
-1.794 1 5
2.378 3 3
3.379 3 4
-1.986 3 2
2.393 3 2
-2.665 0 3
2.597 3 1
0.813 2 2
0.975 3 5
-0.142 0 3
-2.263 0 1
0.042 1 4
-4.178 0 5
-0.914 1 5
0.815 1 4
-0.278 3 4
-0.862 3 4
0.723 0 1
2.512 3 4
-0.091 0 3
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(final-blind-c2_0_2,1,1,0.0001,2);
%fit(final-blind-c2_0_3,1,1,0.0001,3);
%fit(final-blind-c2_0_200,1,1,0.0001,200);
%fit(final-blind-c2_1_2,1,1,1e-10,2);
%fit(final-blind-c2_1_3,1,1,1e-10,3);
%fit(final-blind-c2_1_200,1,1,1e-10,200);
%fit(final-blind-c2_2_2,1024,1,1e-10,2);
%fit(final-blind-c2_2_3,1024,1,1e-10,3);
%fit(final-blind-c2_2_200,1024,1,1e-10,200);
