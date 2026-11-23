data probe; input x y w; datalines;
0.714 0 4
1.543 0 1
-3.924 1 1
-3.069 1 2
-0.903 1 5
-4.1 1 4
-0.579 1 5
0.626 0 5
-1.851 1 5
-0.032 0 5
0.592 0 4
-0.908 1 4
0.372 0 2
0.669 0 3
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(final-blind-c0_0_2,1,1,0.0001,2);
%fit(final-blind-c0_0_3,1,1,0.0001,3);
%fit(final-blind-c0_0_200,1,1,0.0001,200);
%fit(final-blind-c0_1_2,1,1,1e-10,2);
%fit(final-blind-c0_1_3,1,1,1e-10,3);
%fit(final-blind-c0_1_200,1,1,1e-10,200);
%fit(final-blind-c0_2_2,1024,1,1e-10,2);
%fit(final-blind-c0_2_3,1024,1,1e-10,3);
%fit(final-blind-c0_2_200,1024,1,1e-10,200);
