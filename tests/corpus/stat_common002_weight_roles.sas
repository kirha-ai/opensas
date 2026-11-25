/* STAT-COMMON-002: Statistical data selection, missing values, and observation weight interfaces
 * Source: S154 / Chapter 13 / `Introduction to Scoring, Standardization, and Ranking Procedures` (PDF pp. 253–254); S154 / Chapter 22 / `FREQ Statement` (PDF p. 564); S154 / Chapter 22 / `ID Statement` (PDF p. 564); S154 / Chapter 22 / `VAR Statement` (PDF p. 570); S154 / Chapter 22 / `WEIGHT Statement` (PDF p. 570).
 * Discriminates: BY selection and the distinct frequency/analysis weight roles
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
proc sort data=sample; by group; run;
proc means data=sample n mean std sum; by group; var x y; freq freq; weight weight; run;
