/* STAT-FACTOR-001: FACTOR — Data input, variable roles, and basic options
 * Source: S154 / Chapter 44 / `PROC FACTOR Statement` (PDF pp. 2797–2816); S154 / Chapter 44 / `BY Statement` (PDF p. 2816); S154 / Chapter 44 / `FREQ Statement` (PDF pp. 2816–2817); S154 / Chapter 44 / `VAR Statement` (PDF p. 2823); S154 / Chapter 44 / `WEIGHT Statement` (PDF pp. 2823–2824); S154 / Chapter 44 / `Input Data Set` (PDF pp. 2824–2826); S154 / Chapter 44 / `Missing Values` (PDF pp. 2834–2835).
 * Discriminates: Verified default procedure context; explicit statements: VAR
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data SocioEconomics;
input Population School Employment Services HouseValue;
datalines;
5700 12.8 2500 270 25000
1000 10.9 600 10 10000
3400 8.8 1000 10 9000
3800 13.6 1700 140 25000
4000 12.8 1600 140 25000
8200 8.3 2600 60 12000
1200 11.4 400 10 16000
9100 11.5 3300 60 14000
9900 12.5 3400 180 18000
9600 13.7 3600 390 25000
9600 9.6 3300 80 12000
9400 11.4 4000 100 13000
;
proc factor data=SocioEconomics simple corr;
run;
proc factor data=SocioEconomics n=5 score;
run;
proc princomp data=SocioEconomics;
run;
proc factor data=SocioEconomics n=5 score;
ods output StdScoreCoef=Coef;
run;
proc stdize method=ustd mult=.44721 data=Coef out=eigenvectors;
var Factor1-Factor5;
run;
proc print data=eigenvectors;
run;
