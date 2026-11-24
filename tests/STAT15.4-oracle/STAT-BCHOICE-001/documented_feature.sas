/* STAT-BCHOICE-001: BCHOICE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 30 / `PROC BCHOICE Statement` (PDF pp. 1178–1188); S154 / Chapter 30 / `BY Statement` (PDF pp. 1188–1189).
 * Discriminates: Verified default procedure context; explicit statements: BY
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc print data=Sashelp.Margarin (obs=24);
by HouseID Set;
id HouseID Set;
run;
proc bchoice data=Sashelp.Margarin seed=123 nmc=1000 thin=2
nthreads=4 plots=none nbi=200;
class Brand(ref='PPk') HouseID Set;
model Choice = / choiceset=(HouseID Set);
random Brand LogPrice / subject=HouseID remean=(LogInc FamSize)
type=un monitor=(1);
run;
