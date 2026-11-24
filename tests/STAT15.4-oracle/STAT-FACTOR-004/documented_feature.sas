/* STAT-FACTOR-004: FACTOR — Number of Factors to Retain
 * Source: S154 / Chapter 44 / `Number of Factors to Retain` (PDF pp. 2828–2829).
 * Discriminates: Example 44.3: Determining the Number of Factors to Retain
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
run;
proc factor data=Socioeconomics
simple corr;
run;
ods graphics on;
proc factor data=SocioEconomics
parallel(alpha=0.01 nsims=10000 seed=20170229) map
plots=(parallel map);
run;
ods graphics off;
proc factor data=SocioEconomics
nfactors=parallel(alpha=0.01 nsims=10000 seed=20170229);
run;
proc factor data=SocioEconomics
nfactors=map2;
run;
