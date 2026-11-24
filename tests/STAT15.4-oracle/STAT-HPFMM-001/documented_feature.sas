/* STAT-HPFMM-001: HPFMM — Data input, variable roles, and basic options
 * Source: S154 / Chapter 58 / `PROC HPFMM Statement` (PDF pp. 4532–4544); S154 / Chapter 58 / `BY Statement` (PDF pp. 4553–4554); S154 / Chapter 58 / `FREQ Statement` (PDF p. 4554); S154 / Chapter 58 / `ID Statement` (PDF pp. 4554–4555); S154 / Chapter 58 / `WEIGHT Statement` (PDF p. 4570).
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
proc hpfmm data=yeast seed=314159;
model count/n = / k=2;
freq f;
run;
quit;
