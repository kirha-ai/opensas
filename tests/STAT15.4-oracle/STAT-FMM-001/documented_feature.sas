/* STAT-FMM-001: FMM — Data input, variable roles, and basic options
 * Source: S154 / Chapter 46 / `PROC FMM Statement` (PDF pp. 2972–2986); S154 / Chapter 46 / `BY Statement` (PDF pp. 2995–2996); S154 / Chapter 46 / `FREQ Statement` (PDF pp. 2996–2997); S154 / Chapter 46 / `ID Statement` (PDF p. 2997); S154 / Chapter 46 / `WEIGHT Statement` (PDF p. 3015).
 * Discriminates: Verified default procedure context; explicit statements: FREQ
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data yeast;
input count f;
n = 5;
datalines;
0 213
1 128
2 37
3 18
4 3
5 1
;
proc fmm data=yeast seed=314159;
model count/n = / k=2;
freq f;
run;
quit;
