/* S154 physical8624–8629. Paired four-corner design gives beta=(10,3,-1),
   SSE8, DF5, h=3/8 and residuals=(1,-1,-1,1,-1,1,1,-1).
   Centered predictor correlation=.8, eigenvalues=(1.8,.2), condition index3. */
ods graphics off;
data sample;
input x z y;
datalines;
-2 -1 6
-1 -2 8
1 2 10
2 1 16
-2 -1 4
-1 -2 10
1 2 12
2 1 14
;
proc reg data=sample;
model y=x z / influence collinoint;
run;
quit;
