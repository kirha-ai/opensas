/* S154 physical8595–8598. Independent full fit beta=(.2,1.6), SSE5.6;
   dropping observation5 gives beta=(.9,.9), SSE.7, DF2. DATA is unchanged. */
ods graphics off;
data sample;
input x y;
datalines;
0 1
1 2
2 2
3 4
4 8
;
proc reg data=sample outest=fit noprint;
model y=x;
run;
reweight obs.=5 / nolist;
refit;
print;
run;
quit;
data _null_;
set fit;
put _MODEL_ Intercept 12.6 x 12.6 _RMSE_ 12.6;
run;
proc reg data=sample outest=original noprint;
model y=x;
run;
quit;
data _null_;
set original;
put _MODEL_ Intercept 12.6 x 12.6 _RMSE_ 12.6;
run;
