/* S154 physical pp.6652-6653 and520: TESTVALUE changes hypotheses,
   not estimates/CIs. Independent means2,6; MSE10/3; mean variances5/3,10/9.
   DF=1 gives Cauchy p=1-2*atan(t)/pi and CI=mean+/-SE*cot(pi/40).
   Joint F=((2-0)^2/(5/3)+(6-1)^2/(10/9))/2=12.45;
   F(2,1) tail=(1+2F)^(-1/2). Expected values rounded to display precision. */
data sample;
input group y;
datalines;
1 1
1 3
2 4
2 6
2 8
;
run;
proc mixed data=sample;
class group;
model y=group;
lsmestimate group 'A' 1 0, 'B' 0 1 / testvalue=0,1 joint df=1 cl;
ods select LSMEstimates Contrasts;
run;
