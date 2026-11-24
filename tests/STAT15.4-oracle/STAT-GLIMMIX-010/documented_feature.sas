/* STAT-GLIMMIX-010: GLIMMIX — From Penalized Splines to Mixed Models / Knot Selection
 * Source: S154 / Chapter 52 / `From Penalized Splines to Mixed Models` (PDF pp. 3865–3866); S154 / Chapter 52 / `Knot Selection` (PDF pp. 3866–3870).
 * Discriminates: Example 52.15: Comparing Multiple B-Splines
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data spline;
input group y @@;
x = _n_;
datalines;
1 -.020 1 0.199 2 -1.36 1 -.026
2 -.397 1 0.065 2 -.861 1 0.251
1 0.253 2 -.460 2 0.195 2 -.108
1 0.379 1 0.971 1 0.712 2 0.811
2 0.574 2 0.755 1 0.316 2 0.961
2 1.088 2 0.607 2 0.959 1 0.653
1 0.629 2 1.237 2 0.734 2 0.299
2 1.002 2 1.201 1 1.520 1 1.105
1 1.329 1 1.580 2 1.098 1 1.613
2 1.052 2 1.108 2 1.257 2 2.005
2 1.726 2 1.179 2 1.338 1 1.707
2 2.105 2 1.828 2 1.368 1 2.252
1 1.984 2 1.867 1 2.771 1 2.052
2 1.522 2 2.200 1 2.562 1 2.517
1 2.769 1 2.534 2 1.969 1 2.460
1 2.873 1 2.678 1 3.135 2 1.705
1 2.893 1 3.023 1 3.050 2 2.273
2 2.549 1 2.836 2 2.375 2 1.841
1 3.727 1 3.806 1 3.269 1 3.533
1 2.948 2 1.954 2 2.326 2 2.017
1 3.744 2 2.431 2 2.040 1 3.995
2 1.996 2 2.028 2 2.321 2 2.479
2 2.337 1 4.516 2 2.326 2 2.144
2 2.474 2 2.221 1 4.867 2 2.453
1 5.253 2 3.024 2 2.403 1 5.498
;
proc sgplot data=spline;
scatter y=y x=x / group=group name="data";
keylegend "data" / title="Group";
run;
proc glimmix data=spline outdesign=x;
class group;
effect spl = spline(x);
model y = group spl*group / s noint;
output out=gmxout pred=p;
run;
proc sgplot data=gmxout;
series y=p x=x / group=group name="fit";
scatter y=y x=x / group=group;
keylegend "fit" / title="Group";
run;
proc glimmix data=spline;
class group;
effect spl = spline(x);
model y = group spl*group / s noint;
estimate 'Group 1, x=20' group 1 group *spl [1,1 20] / e;
estimate 'Group 2, x=20' group 0 1 group *spl [1,2 20];
estimate 'Diff at x=20 ' group 1 -1 group*spl [1,1 20] [-1,2 20];
run;
ods select Estimates;
proc glimmix data=spline;
class group;
effect spl = spline(x);
model y = group spl*group / s;
estimate 'Diff at x= 0' group 1 -1 group*spl [1,1 0] [-1,2 0],
'Diff at x= 5' group 1 -1 group*spl [1,1 5] [-1,2 5],
'Diff at x=10' group 1 -1 group*spl [1,1 10] [-1,2 10],
'Diff at x=15' group 1 -1 group*spl [1,1 15] [-1,2 15],
'Diff at x=20' group 1 -1 group*spl [1,1 20] [-1,2 20],
'Diff at x=25' group 1 -1 group*spl [1,1 25] [-1,2 25],
'Diff at x=30' group 1 -1 group*spl [1,1 30] [-1,2 30],
'Diff at x=35' group 1 -1 group*spl [1,1 35] [-1,2 35],
'Diff at x=40' group 1 -1 group*spl [1,1 40] [-1,2 40],
'Diff at x=45' group 1 -1 group*spl [1,1 45] [-1,2 45],
'Diff at x=50' group 1 -1 group*spl [1,1 50] [-1,2 50],
'Diff at x=55' group 1 -1 group*spl [1,1 55] [-1,2 55],
'Diff at x=60' group 1 -1 group*spl [1,1 60] [-1,2 60],
'Diff at x=65' group 1 -1 group*spl [1,1 65] [-1,2 65],
'Diff at x=70' group 1 -1 group*spl [1,1 70] [-1,2 70],
'Diff at x=75' group 1 -1 group*spl [1,1 75] [-1,2 75],
'Diff at x=80' group 1 -1 group*spl [1,1 80] [-1,2 80] /
adjust=sim(seed=1) stepdown;
run;
