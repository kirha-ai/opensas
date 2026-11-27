/* S154 physical pp.8588–8589,8644–8647; statistical formulas pp.113–114.
   Orthogonal Walsh x,z,xz,w all have squared norm8.
   y1=10+2*x+z+x*z; y2=20+x+3*z+w.
   E=8I, H=[[40,40],[40,80]], residual DF=5.
   y1-y2 gives E=16,H=40 and exact F(2,5)=6.25. */
ods graphics off;
data sample;
input x z y1 y2;
datalines;
-1 -1 8 15
1 -1 10 17
-1 1 8 21
1 1 14 23
-1 -1 8 17
1 -1 10 19
-1 1 8 23
1 1 14 25
;
proc reg data=sample;
model y1 y2=x z;
mtest / print;
contrast: mtest y1=y2;
run;
quit;
