/* S154 physical pp.8613–8617; exact orthogonal reference in reg_selection_tests.
   y=10+4*x+2*z+w/4+x*z; SST=337/2, full SSE=8, full MSE=2. */
ods graphics off;
data sample;
input x z w y;
datalines;
-1 -1 -1 4.75
1 -1 -1 10.75
-1 1 -1 6.75
1 1 -1 16.75
-1 -1 1 5.25
1 -1 1 11.25
-1 1 1 7.25
1 1 1 17.25
;
proc reg data=sample outest=selected noprint;
r2: model y=x z w / selection=rsquare best=1 cp sse;
ar2: model y=x z w / selection=adjrsq best=2 cp sse;
cp: model y=x z w / selection=cp best=2 cp sse;
fwd: model y=x z w / selection=forward cp sse;
bwd: model y=x z w / selection=backward cp sse;
step: model y=x z w / selection=stepwise cp sse;
maxr: model y=x z w / selection=maxr stop=2 cp sse;
minr: model y=x z w / selection=minr stop=2 cp sse;
run;
quit;
data _null_;
set selected;
put _MODEL_ _IN_ 2. _EDF_ 2. _SSE_ 8.2 _CP_ 8.2 Intercept 8.2 x 8.2 z 8.2 w 8.2 _RMSE_ 8.5;
run;
