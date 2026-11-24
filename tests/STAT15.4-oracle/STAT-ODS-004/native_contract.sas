/* STAT-ODS-004: ODS — The SAS Results Window / The ODS PATH Statement
 * Source: S154 / Chapter 23 / `The SAS Results Window` (PDF pp. 592–594); S154 / Chapter 23 / `The ODS PATH Statement` (PDF p. 594).
 * Discriminates: ODS object paths, TRACE names and table selection
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
ods trace on; ods select ParameterEstimates; proc reg data=sample; model y=x z; run; quit; ods select all; ods trace off;
