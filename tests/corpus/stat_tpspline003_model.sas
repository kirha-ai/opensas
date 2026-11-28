/* STAT-TPSPLINE-003: MODEL statement forms and options (S154 Chapter 125,
 * MODEL Statement pp.10303-10306; Computational Formulas pp.10308-10312)
 * against a SAS 15.4 reference run of this program: several dependent
 * variables (missing values counted per dependent), regression variables
 * (semiparametric model), one, two, three and four smoothing variables,
 * M=3, M= below d/2 (WARNING, default used), LAMBDA= lists (shown on the
 * log10(n*Lambda) scale, given order), LOGNLAMBDA= TO lists (decreasing),
 * LAMBDA0=, LOGNLAMBDA0=, DF=, RANGE=, DISTANCE=, the precedence warnings
 * and OUTPUT with two dependents. Data: the Getting Started data of the
 * chapter (published sample data) with derived variables.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
ods graphics off;
data Measure;
input x1 x2 y @@;
datalines;
-1.0 -1.0 15.54483570 -1.0 -1.0 15.76312613
-.5 -1.0 18.67397826 -.5 -1.0 18.49722167
.0 -1.0 19.66086310 .0 -1.0 19.80231311
.5 -1.0 18.59838649 .5 -1.0 18.51904737
1.0 -1.0 15.86842815 1.0 -1.0 16.03913832
-1.0 -.5 10.92383867 -1.0 -.5 11.14066546
-.5 -.5 14.81392847 -.5 -.5 14.82830425
.0 -.5 16.56449698 .0 -.5 16.44307297
.5 -.5 14.90792284 .5 -.5 15.05653924
1.0 -.5 10.91956264 1.0 -.5 10.94227538
-1.0 .0 9.61492010 -1.0 .0 9.64648093
-.5 .0 14.03133439 -.5 .0 14.03122345
.0 .0 15.77400253 .0 .0 16.00412514
.5 .0 13.99627680 .5 .0 14.02826553
1.0 .0 9.55700164 1.0 .0 9.58467047
-1.0 .5 11.20625177 -1.0 .5 11.08651907
-.5 .5 14.83723493 -.5 .5 14.99369172
.0 .5 16.55494349 .0 .5 16.51294369
.5 .5 14.98448603 .5 .5 14.71816070
1.0 .5 11.14575565 1.0 .5 11.17168689
-1.0 1.0 15.82595514 -1.0 1.0 15.96022497
-.5 1.0 18.64014953 -.5 1.0 18.56095997
.0 1.0 19.54375504 .0 1.0 19.80902641
.5 1.0 18.56884576 .5 1.0 18.61010439
1.0 1.0 15.86586951 1.0 1.0 15.90136745
;
data m2; set Measure; z = mod(_n_,5)/4; x3 = mod(_n_*7,11)/10; y2 = y + x1*x2 + z; if _n_ = 3 then y2 = .;
 y3 = 1 + x1 + 2*x2 + (mod(_n_,2)-0.5); run;
title 'A two dependents'; proc tpspline data=m2; model y y2 = (x1 x2) / lognl=(-4 -3) lognl0=-3; run;
title 'B regression variable'; proc tpspline data=m2; model y = z (x1 x2) / lognl0=-3; output out=ob pred adiag; run;
proc print data=ob(obs=3); var x1 x2 z y P_y Adiag_y; run;
title 'C one smoothing variable'; proc tpspline data=m2; model y = (x1) / lognl0=-1; run;
title 'D three smoothing variables'; proc tpspline data=m2; model y = (x1 x2 x3) / lognl0=-3; run;
title 'E M=3'; proc tpspline data=m2; model y = (x1 x2) / m=3 lognl0=-3.5; run;
title 'F LAMBDA= list'; proc tpspline data=m2; model y = (x1 x2) / lambda=(0.0001 0.00001 0.001) lognl0=-3; run;
title 'G DF=10'; proc tpspline data=m2; model y = (x1 x2) / df=10; run;
title 'H RANGE='; proc tpspline data=m2; model y = (x1 x2) / range=(-3,-2); run;
title 'I LAMBDA0='; proc tpspline data=m2; model y = (x1 x2) / lambda0=0.0001; run;
title 'K LAMBDA0= and LOGNL0='; proc tpspline data=m2; model y = (x1 x2) / lambda0=0.0001 lognl0=-3; run;
title 'L M=1'; proc tpspline data=m2; model y = (x1 x2) / m=1 lognl0=-3; run;
title 'P two regression variables'; proc tpspline data=m2; model y = z x3 (x1) / lognl0=-0.5; run;
title 'Q LOGNL= and LAMBDA='; proc tpspline data=m2; model y = (x1 x2) / lognl=(-4 -3) lambda=(0.001) lognl0=-3; run;
title 'R LOGNL0= and DF='; proc tpspline data=m2; model y = (x1 x2) / lognl0=-3 df=5; run;
title 'S four smoothing variables'; proc tpspline data=m2; model y = (x1 x2 x3 z) / lognl0=-3; run;
title 'T1 DISTANCE='; proc tpspline data=m2; model y = (x1 x2) / distance=1.2 lognl0=-1.5; output out=o3 pred; run;
proc print data=o3(obs=4); var x1 x2 y P_y; run;
title 'T3 LAMBDA= not positive'; proc tpspline data=m2; model y = (x1 x2) / lambda=(0 0.001) lognl0=-3; run;
title 'T4 DF=0'; proc tpspline data=m2; model y = (x1 x2) / df=0 lognl0=-3; run;
title 'T7 decreasing list'; proc tpspline data=m2; model y = (x1 x2) / lognl=(-2 to -4 by -1) lognl0=-3; run;
title 'T19 M=3 one variable'; proc tpspline data=m2; model y = (x1) / m=3 lognl0=0; run;
title 'T21 DF= with a regression variable'; proc tpspline data=m2; model y = z (x1 x2) / df=12; run;
title 'U9 RANGE= and LOGNL0='; proc tpspline data=m2; model y = (x1 x2) / range=(-3, -1) lognl0=-2; run;
title 'V two dependents OUTPUT'; proc tpspline data=m2; model y y3 = (x1 x2) / lognl0=-3; output out=o4 pred resid; run;
proc print data=o4(obs=2); var x1 x2 y y3 P_y P_y3 R_y R_y3; run;
