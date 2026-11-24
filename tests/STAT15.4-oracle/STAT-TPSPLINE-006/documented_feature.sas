/* STAT-TPSPLINE-006: TPSPLINE — OUTPUT
 * Source: S154 / Chapter 125 / `OUTPUT Statement` (PDF pp. 10306–10307).
 * Discriminates: Getting Started: TPSPLINE Procedure; explicit statements: OUTPUT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

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
data Measure1;
set Measure;
run;
proc sort data=Measure1;
by x2 x1;
run;
data Measure1;
set Measure1;
if mod(_N_, 2) = 0 then x1=x1+0.001;
run;
filename _grfile temp; goptions device=svg gsfname=_grfile;
proc g3d data=Measure1;
scatter x2*x1=y /size=.5
zmin=9 zmax=21
zticknum=4;
title "Raw Data";
run;
ods graphics on;
proc tpspline data=Measure;
model y=(x1 x2) /lognlambda=(-4 to -2.5 by 0.1);
output out=estimate pred uclm lclm;
run;
proc print data=estimate;
run;
data pred;
do x1=-1 to 1 by 0.1;
do x2=-1 to 1 by 0.1;
output;
end;
end;
run;
proc tpspline data=measure;
model y=(x1 x2)/lognlambda0=-3.4762;
score data=pred out=predy;
run;
proc template;
define statgraph surface;
dynamic _X _Y _Z _T;
begingraph /designheight=360;
entrytitle _T;
layout overlay3d/rotate=120 cube=false xaxisopts=(label="x1")
yaxisopts=(label="x2") zaxisopts=(label="P_y");
surfaceplotparm x=_X y=_Y z=_Z;
endlayout;
endgraph;
end;
run;
proc sgrender data=predy template=surface;
dynamic _X='x1' _Y='x2' _Z='P_y'
_T='Plot of Fitted Surface on a Fine Grid';
run;
