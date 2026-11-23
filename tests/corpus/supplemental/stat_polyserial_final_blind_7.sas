data probe; input x y w; datalines;
-1.168 0 1
0.75 0 1
-0.965 0 4
0.226 1 4
-0.427 0 3
-0.174 1 1
-3.531 0 1
1.366 1 1
-0.11 2 2
-1.065 0 2
0.794 2 3
1.23 2 3
-0.778 0 4
-0.604 0 2
-1.392 0 4
-0.597 0 2
1.469 2 3
0.515 2 4
-0.14 0 4
-2.19 0 1
1.341 1 2
-0.12 0 5
-3.123 0 1
-0.881 0 5
-1.656 0 2
-1.946 0 5
-0.91 0 1
-1.161 1 5
1.24 0 3
-3.057 0 2
0.911 0 5
-0.556 0 1
-3.747 0 2
1.193 1 3
-1.506 0 4
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(final-blind-c7_0_2,1,1,0.0001,2);
%fit(final-blind-c7_0_3,1,1,0.0001,3);
%fit(final-blind-c7_0_200,1,1,0.0001,200);
%fit(final-blind-c7_1_2,1,1,1e-10,2);
%fit(final-blind-c7_1_3,1,1,1e-10,3);
%fit(final-blind-c7_1_200,1,1,1e-10,200);
%fit(final-blind-c7_2_2,1024,1,1e-10,2);
%fit(final-blind-c7_2_3,1024,1,1e-10,3);
%fit(final-blind-c7_2_200,1024,1,1e-10,200);
