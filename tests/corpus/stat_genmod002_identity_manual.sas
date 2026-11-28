/* STAT-GENMOD-002: PROC GENMOD default model (no DIST=/LINK=: Normal with the
   identity link, ML scale) on a case solvable by hand. Invented data.
   n=6, xbar=3.5, ybar=4.5, Sxx=17.5, Sxy=16.5:
     slope = 16.5/17.5 = 0.942857, intercept = 4.5 - 3.5*slope = 1.2
     SSE = Syy - Sxy^2/Sxx = 17.5 - 15.557143 = 1.942857 (deviance = Pearson)
     scale = sqrt(SSE/6) = 0.569043 (ML divisor n), scaled deviance = n = 6
     se(slope) = scale/sqrt(Sxx) = 0.136027
     se(intercept) = scale*sqrt(1/6 + 3.5^2/17.5) = 0.529750
     se(scale) = scale/sqrt(12) = 0.164268
     limits(scale) = scale*exp(-/+ 1.959964*se/scale) = 0.323165, 1.001995
     log L = -3*(log(2*pi*SSE/6) + 1) = -5.130832
     AIC = -2 log L + 2*3 = 16.261663, AICC = AIC + 24/2 = 28.261663
     BIC = -2 log L + 3*log(6) = 15.636942
     DF = 6 - 2 = 4; Wald chi-square = (estimate/se)^2. */
options nocenter;
title;
data line;
input x y;
datalines;
1 2
2 3
3 5
4 4
5 6
6 7
;
proc genmod data=line;
model y = x;
run;
