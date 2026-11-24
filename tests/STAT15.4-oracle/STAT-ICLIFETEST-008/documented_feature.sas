/* STAT-ICLIFETEST-008: ICLIFETEST — Official examples and feature integration regression
 * Source: S154 / Chapter 69 / `Examples: ICLIFETEST Procedure` (PDF pp. 5190–5196).
 * Discriminates: Example 69.1: Analyzing Data with Observations below a Limit of Detection
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data temp;
input C1 C2;
datalines;
. 3
4 4
6 6
8 8
. 10
12 12
;
proc iclifetest data=temp method=turnbull plots=survival(failure)
impute(seed=1234);
time (c1,c2);
run;
