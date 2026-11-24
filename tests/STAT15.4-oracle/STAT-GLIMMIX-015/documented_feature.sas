/* STAT-GLIMMIX-015: GLIMMIX — NLOPTIONS / PARMS
 * Source: S154 / Chapter 52 / `NLOPTIONS Statement` (PDF pp. 3786–3787); S154 / Chapter 52 / `PARMS Statement` (PDF pp. 3791–3796).
 * Discriminates: Example 52.10: Multiple Trends Correspond to Multiple Extrema in Profile Likelihoods; explicit statements: PARMS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc print data=Sashelp.enso(obs=10);
run;
data tdata;
do covp1=0,0.0005,0.05,0.1,0.2,0.5,
1,2,3,4,5,6,8,10,15,20,50,
75,100,125,140,150,160,175,
200,225,250,275,300,350;
output;
end;
run;
ods select FitStatistics CovParms CovTests;
proc glimmix data=sashelp.enso noprofile;
model pressure = year;
random year / type=rsmooth knotmethod=equal(50);
parms (2) (10);
covtest tdata=tdata / parms;
ods output covtests=ct;
run;
proc sgplot data=ct;
series y=objective x=covp1;
run;
proc glimmix data=sashelp.enso;
model pressure = year;
random year / type=rsmooth knotmethod=equal(50);
parms (0) (10);
output out=gmxout1 pred=pred1;
run;
proc glimmix data=sashelp.enso;
model pressure = year;
random year / type=rsmooth knotmethod=equal(50);
output out=gmxout2 pred=pred2;
parms (2) (10);
run;
proc glimmix data=sashelp.enso;
model pressure = year;
random year / type=rsmooth knotmethod=equal(50);
output out=gmxout3 pred=pred3;
parms (200) (10);
run;
data plotthis;
merge gmxout1 gmxout2 gmxout3;
run;
proc sgplot data=plotthis;
scatter x=year y=Pressure;
series x=year y=pred1 /
lineattrs = (pattern=solid thickness=2)
legendlabel = "Var[RSmooth] = 0.0005"
name = "pred1";
series x=year y=pred2 /
lineattrs = (pattern=dot thickness=2)
legendlabel = "Var[RSmooth] = 3.5719"
name = "pred2";
series x=year y=pred3 /
lineattrs = (pattern=dash thickness=2)
legendlabel = "Var[RSmooth] = 186.71"
name = "pred3";
keylegend "pred1" "pred2" "pred3" / across=2;
run;
data foot_mv;
input yr b1 b2 b3 k1 k2 k3;
sire = _n_;
datalines;
1 1 0 0 52 25 0
1 1 0 0 49 17 1
1 1 0 0 50 13 1
1 1 0 0 42 9 0
1 1 0 0 74 15 0
1 1 0 0 54 8 0
1 1 0 0 96 12 0
1 -1 1 0 57 52 9
1 -1 1 0 55 27 5
1 -1 1 0 70 36 4
1 -1 1 0 70 37 3
1 -1 1 0 82 21 1
1 -1 1 0 75 19 0
1 -1 -1 0 17 12 10
1 -1 -1 0 13 23 3
1 -1 -1 0 21 17 3
-1 0 0 1 37 41 23
-1 0 0 1 47 24 12
-1 0 0 1 46 25 9
-1 0 0 1 79 32 11
-1 0 0 1 50 23 5
-1 0 0 1 63 18 8
-1 0 0 -1 30 20 9
-1 0 0 -1 31 33 3
-1 0 0 -1 28 18 4
-1 0 0 -1 42 27 4
-1 0 0 -1 35 22 2
-1 0 0 -1 33 18 3
-1 0 0 -1 35 17 4
-1 0 0 -1 26 13 2

run;
quit;
