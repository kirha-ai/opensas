/* S154 physical8598–8599,8610 and8669. Independent four-row model:
   beta=(10,3,-1), Gslopes=[[5/18,-2/9],[-2/9,5/18]], SSE=4, DF=1.
   TEST x,z has SS52. PRINT inverse=[[10,8],[8,10]], delta=(3,-1),
   inverse*delta=(22,14). Native intermediate object names follow the guide. */
ods graphics off;
data sample;
input x z y;
datalines;
-2 -1 6
-1 -2 8
1 2 10
2 1 16
;
proc reg data=sample;
model y=x z;
run;
one: test x,z / print;
run;
two: test 2*x-3*z=5;
run;
quit;
