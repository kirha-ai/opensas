/* STAT-LIFETEST-001: LIFETEST — Data input, variable roles, and basic options
 * Source: S154 / Chapter 77 / `PROC LIFETEST Statement` (PDF pp. 5650–5662); S154 / Chapter 77 / `BY Statement` (PDF pp. 5662–5663); S154 / Chapter 77 / `FREQ Statement` (PDF p. 5663); S154 / Chapter 77 / `ID Statement` (PDF p. 5663); S154 / Chapter 77 / `STRATA Statement` (PDF pp. 5663–5668); S154 / Chapter 77 / `WEIGHT Statement` (PDF p. 5670); S154 / Chapter 77 / `Missing Values` (PDF pp. 5670–5671).
 * Discriminates: Verified default procedure context; explicit statements: STRATA
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data survival;
input time status group $;
datalines;
1 1 A
2 0 A
2 1 A
4 1 A
5 0 A
1 0 B
3 1 B
4 1 B
6 0 B
7 1 B
;
run;
proc lifetest data=survival;
time time*status(0);
strata group;
run;
