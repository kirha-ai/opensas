/* STAT-NLIN-008: NLIN — BOUNDS / PARAMETERS
 * Source: S154 / Chapter 88 / `BOUNDS Statement` (PDF pp. 7000–7001); S154 / Chapter 88 / `PARAMETERS Statement` (PDF pp. 7008–7011).
 * Discriminates: Example 88.4: Affecting Curvature through Parameterization; explicit statements: PARAMETERS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data logistic;
input dose y;
logdose = log(dose);
datalines;
0.009 106.56
0.035 94.12
0.07 89.76
0.15 60.21
0.20 39.95
0.28 21.88
0.50 7.46
;
proc sgplot data=logistic;
scatter y=y x=dose;
xaxis type=log logstyle=linear;
run;
proc nlin data=logistic bias hougaard nlinmeasures;
parameters alpha=100 beta=3 gamma=300;
delta = 0;
Switch = 1/(1+gamma*exp(beta*log(dose)));
model y = delta + (alpha - delta)*Switch;
run;
proc nlin data=logistic bias hougaard;
parameters alpha=100 beta=3 LD50=0.15;
delta = 0;
Switch = 1/(1+exp(beta*log(dose/LD50)));
model y = delta + (alpha - delta)*Switch;
output out=nlinout pred=p lcl=lcl ucl=ucl;
run;
proc nlin data=logistic bias hougaard nlinmeasures;
parameters alpha=100 mustar=20 LD50=0.15;
delta = 0;
xstar = 0.3;
beta = log((alpha - mustar)/(mustar - delta)) / log(xstar/LD50);
Switch = 1/(1+exp(beta *log(dose/LD50)));
model y = delta + (alpha - delta)*Switch;
output out=nlinout pred=p lcl=lcl ucl=ucl;
run;
