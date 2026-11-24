/* STAT-DISTANCE-001: DISTANCE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 43 / `PROC DISTANCE Statement` (PDF pp. 2747–2754); S154 / Chapter 43 / `VAR Statement` (PDF pp. 2754–2759); S154 / Chapter 43 / `ID Statement` (PDF p. 2759); S154 / Chapter 43 / `COPY Statement` (PDF p. 2759); S154 / Chapter 43 / `BY Statement` (PDF pp. 2759–2760); S154 / Chapter 43 / `FREQ Statement` (PDF p. 2760); S154 / Chapter 43 / `WEIGHT Statement` (PDF pp. 2760–2761); S154 / Chapter 43 / `Missing Values` (PDF p. 2768); S154 / Chapter 43 / `Formatted versus Unformatted Values` (PDF pp. 2768–2769).
 * Discriminates: Verified default procedure context; explicit statements: VAR, FREQ, WEIGHT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data sample;
input x z y group $ weight freq;
datalines;
1 1 4 A 1 1
2 1 6 A 2 1
3 2 7 A 1 2
4 1 9 A 1 1
5 3 13 A 2 1
6 2 12 A 1 1
7 4 17 B 1 1
8 3 19 B 2 2
9 5 20 B 1 1
10 3 23 B 1 1
11 5 25 B 2 1
12 4 24 B 1 1
;
run;
proc distance data=sample method=euclid out=dist;
var interval(x z /std=std);
run;
proc print data=dist noobs;
run;
