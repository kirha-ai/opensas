/* STAT-FACTOR-002: FACTOR — Factor extraction, communalities, and the default factor solution
 * Source: S154 / Chapter 44 / `Getting Started: FACTOR Procedure` (PDF pp. 2792–2797); S154 / Chapter 44 / `Overview: FACTOR Procedure` (PDF pp. 2784–2792).
 * Discriminates: Example 44.1: Principal Component Analysis
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
