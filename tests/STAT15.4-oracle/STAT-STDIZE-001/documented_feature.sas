/* STAT-STDIZE-001: STDIZE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 115 / `PROC STDIZE Statement` (PDF pp. 9455–9461); S154 / Chapter 115 / `BY Statement` (PDF pp. 9461–9462); S154 / Chapter 115 / `FREQ Statement` (PDF p. 9462); S154 / Chapter 115 / `VAR Statement` (PDF pp. 9462–9463); S154 / Chapter 115 / `WEIGHT Statement` (PDF pp. 9463–9464); S154 / Chapter 115 / `Missing Values` (PDF p. 9469).
 * Discriminates: Verified default procedure context; explicit statements: BY, FREQ, VAR, WEIGHT
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
proc sort data=sample;
by group;
run;
proc stdize data=sample out=standardized method=std pstat;
by group;
var x z y;
run;
proc print data=standardized noobs;
format _numeric_ best32.;
run;
