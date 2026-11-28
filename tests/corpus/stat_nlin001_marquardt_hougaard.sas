/* STAT-NLIN-001: PROC NLIN default listing of a METHOD=MARQUARDT fit with a
   PARMS starting-value grid and HOUGAARD (SAS/STAT 15.4 ch.88, PROC NLIN
   statement pp.6987-6998). Data: the published Getting Started enzyme sample
   of the chapter. Expected: the SAS reference listing of this program (Grid
   Search, Iterative Phase, Estimation Summary, ANOVA, parameter estimates
   with Hougaard skewness, approximate correlation matrix). */
options nocenter;
title;
data Enzyme;
input Concentration Velocity @@;
datalines;
0.26 124.7 0.30 126.9
0.48 135.9 0.50 137.6
0.54 139.6 0.68 141.1
0.82 142.8 1.14 147.6
1.28 149.8 1.38 149.4
1.80 153.9 2.30 152.5
2.44 154.5 2.48 154.7
;
proc nlin data=Enzyme method=marquardt hougaard;
parms theta1=155
theta2=0 to 0.07 by 0.01;
model Velocity = theta1*Concentration / (theta2 + Concentration);
run;
