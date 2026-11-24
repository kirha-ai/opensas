/* STAT-VARCLUS-001: VARCLUS — Data input, variable roles, and basic options
 * Source: S154 / Chapter 129 / `PROC VARCLUS Statement` (PDF pp. 10700–10707); S154 / Chapter 129 / `BY Statement` (PDF pp. 10707–10708); S154 / Chapter 129 / `FREQ Statement` (PDF p. 10708); S154 / Chapter 129 / `VAR Statement` (PDF pp. 10708–10709); S154 / Chapter 129 / `WEIGHT Statement` (PDF p. 10709); S154 / Chapter 129 / `Missing Values` (PDF p. 10709).
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

proc varclus data=sashelp.iris maxclusters=2 outstat=structure;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
proc print data=structure(obs=15) noobs;
run;
