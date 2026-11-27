/* S154 physical pp.8593–8595. Independent calculation in reg_restrict_tests:
   X'X slopes=[[10,8],[8,10]], unrestricted beta=(10,3,-1).
   z=0 implies beta=(10,11/5,0), SSE=38/5, df=2, MSE=19/5.
   Covariance=diag(19/20,19/50,0). */
ods graphics off;
data sample;
input x z y;
datalines;
-2 -1 6
-1 -2 8
1 2 10
2 1 16
;
proc reg data=sample outest=est covout;
model y=x z;
restrict x=0;
restrict z=0;
run;
quit;
data _null_;
set est;
put _TYPE_ _NAME_ Intercept 8.5 x 8.5 z 8.5 _RMSE_ 8.5;
run;
