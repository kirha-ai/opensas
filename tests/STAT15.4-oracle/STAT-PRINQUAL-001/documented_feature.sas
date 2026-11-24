/* STAT-PRINQUAL-001: PRINQUAL — Data input, variable roles, and basic options
 * Source: S154 / Chapter 99 / `PROC PRINQUAL Statement` (PDF pp. 8040–8048); S154 / Chapter 99 / `BY Statement` (PDF pp. 8048–8049); S154 / Chapter 99 / `FREQ Statement` (PDF p. 8049); S154 / Chapter 99 / `ID Statement` (PDF p. 8049); S154 / Chapter 99 / `WEIGHT Statement` (PDF p. 8057); S154 / Chapter 99 / `Missing Values` (PDF p. 8063).
 * Discriminates: Verified default procedure context; explicit statements: WEIGHT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc prinqual data=sashelp.class out=scaled;
transform identity(height weight age);
run;
proc print data=scaled(obs=5) noobs;
run;
