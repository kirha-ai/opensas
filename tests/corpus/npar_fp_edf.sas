/* S154 physical pp.7244-7249, independent synthetic placements/CDF jumps.
   A=(1,2,3), B=(2,4,5): placementsA=(0,.5,1), placementsB=(1.5,3,3).
   FPdifference=6, denominator=sqrt(13), Z=6/sqrt(13), one-tail=.04804616472783664.
   EDF D+=2/3,D-=0,KS=1/3,KSa=sqrt(2/3); exp(-4/3)=.2635971381.
   Kolmogorov exponential-series tail=.5175506635818756. */
options nodate nonumber;
data sample;
input group $ x;
datalines;
A 1
A 2
A 3
B 2
B 4
B 5
;
run;
ods graphics on;
ods trace on;
ods select FPTest KS2Stats FPBoxPlot EDFPlot;
proc npar1way data=sample fp(refclass=1) d plots(only)=(fpboxplot edfplot);
class group;
var x;
run;
ods trace off;
ods graphics off;
