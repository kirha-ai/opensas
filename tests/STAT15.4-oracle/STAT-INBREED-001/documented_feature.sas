/* STAT-INBREED-001: INBREED — Data input, variable roles, and basic options
 * Source: S154 / Chapter 71 / `PROC INBREED Statement` (PDF pp. 5274–5276); S154 / Chapter 71 / `BY Statement` (PDF pp. 5276–5277); S154 / Chapter 71 / `CLASS Statement` (PDF p. 5277); S154 / Chapter 71 / `VAR Statement` (PDF p. 5278); S154 / Chapter 71 / `Missing Values` (PDF pp. 5278–5279).
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

data pedigree;
input animal $ sire $ dam $;
datalines;
A . .
B . .
C A B
D A B
E C D
;
run;
proc inbreed data=pedigree covar matrix;
var animal sire dam;
run;
