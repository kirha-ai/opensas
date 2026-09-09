/* PROC UNIVARIATE WEIGHT: weighted moments to a dataset (WEIGHT-uni-impl).
   x={10,20,30}, wt={3,1,1}: Sum Weights=5, Sum Obs=Σwx=10*3+20+30=80,
   weighted Mean=80/5=16 (unweighted would be 20 — proves weights apply),
   CSS=3*(10-16)^2+(20-16)^2+(30-16)^2=108+16+196=320, Var=320/(3-1)=160,
   USS=3*100+400+900=1600. */
data w; input x wt; datalines;
10 3
20 1
30 1
;
run;
proc univariate data=w noprint;
  var x;
  weight wt;
  output out=s n=n mean=mean sum=sum css=css uss=uss var=var;
run;
proc print data=s; run;
