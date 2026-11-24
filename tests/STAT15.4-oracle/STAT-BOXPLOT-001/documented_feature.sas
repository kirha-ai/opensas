/* STAT-BOXPLOT-001: BOXPLOT — Data input, variable roles, and basic options
 * Source: S154 / Chapter 32 / `PROC BOXPLOT Statement` (PDF pp. 1376–1377); S154 / Chapter 32 / `BY Statement` (PDF pp. 1377–1378); S154 / Chapter 32 / `ID Statement` (PDF p. 1378); S154 / Chapter 32 / `Input Data Sets` (PDF pp. 1411–1414); S154 / Chapter 32 / `Missing Values` (PDF p. 1416).
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

filename _grfile temp; goptions device=svg gsfname=_grfile;
proc sort data=sashelp.cars out=cars; by Origin; run;
ods graphics on;
proc boxplot data=cars; plot MPG_City*Origin; run;
ods graphics off;
proc means data=cars n mean std min q1 median q3 max; class Origin; var MPG_City; run;
