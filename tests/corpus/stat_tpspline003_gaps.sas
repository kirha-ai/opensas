/* expect-rc: 2
 * STAT-TPSPLINE-003: valid MODEL requests whose SAS 15.4 results are not
 * reproduced fail visibly with no listing: a GCV minimum at the upper end of
 * the smoothing-parameter search (SAS stops at a data-dependent limit, e.g.
 * 3.6093 here), the lower end of the search (GCV decreasing toward
 * interpolation; DF= above the unique design points), DF= at or below the
 * polynomial-space dimension, DISTANCE= with regression variables, DF= with
 * RANGE=, several dependents with BY, a missing regression-variable value,
 * M= above 10 and more than six smoothing variables.
 * Data: the Getting Started data of the chapter (published sample data).
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
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
data m2; set Measure; z = mod(_n_,5)/4; x3 = mod(_n_*7,11)/10;
 y3 = 1 + x1 + 2*x2 + (mod(_n_,2)-0.5); g = (_n_ > 25);
 a1=x1; a2=x2; a3=x3; a4=z; a5=x1*x2; a6=x1*x1; a7=x2*x2; run;
data zmiss; set m2; if _n_ = 4 then z = .; run;
proc tpspline data=m2; model y3 = (x1 x2); run;
proc tpspline data=m2; model y = (x1 x2 x3); run;
proc tpspline data=m2; model y = (x1 x2) / df=30; run;
proc tpspline data=m2; model y = (x1 x2) / df=2; run;
proc tpspline data=m2; model y = z (x1 x2) / distance=1; run;
proc tpspline data=m2; model y = (x1 x2) / df=10 range=(-3,-1); run;
proc tpspline data=m2; by g; model y y3 = (x1 x2); run;
proc tpspline data=zmiss; model y = z (x1 x2); run;
proc tpspline data=m2; model y = (x1 x2) / m=11; run;
proc tpspline data=m2; model y = (a1 a2 a3 a4 a5 a6 a7); run;
