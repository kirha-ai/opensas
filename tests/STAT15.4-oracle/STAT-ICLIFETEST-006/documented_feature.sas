/* STAT-ICLIFETEST-006: ICLIFETEST — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 69 / `Displayed Output` (PDF pp. 5185–5188); S154 / Chapter 69 / `ODS Table Names` (PDF pp. 5188–5189).
 * Discriminates: Getting Started: ICLIFETEST Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods trace on;
data RT;
input lTime rTime @@;
trt = ' RT';
datalines;
45 . 25 37 37 .
6 10 46 . 0 5
0 7 26 40 18 .
46 . 46 . 24 .
46 . 27 34 36 .
7 16 36 44 5 11
17 . 46 . 19 35
7 14 36 48 17 25
37 44 37 . 24 .
0 8 40 . 32 .
4 11 17 25 33 .
15 . 46 . 19 26
11 15 11 18 37 .
22 . 38 . 34 .
46 . 5 12 36 .
46 .
;
data RCT;
input lTime rTime @@;
trt = 'RCT';
datalines;
8 12 0 5 30 34
0 22 5 8 13 .
24 31 12 20 10 17
17 27 11 . 8 21
17 23 33 40 4 9
24 30 31 . 11 .
16 24 13 39 14 19
13 . 19 32 4 8
11 13 34 . 34 .
16 20 13 . 30 36
18 25 16 24 18 24
17 26 35 . 16 60
32 . 15 22 35 39
23 . 11 17 21 .
44 48 22 32 11 20
14 17 10 35 48 .
;
data BCS;
set RT RCT;
run;
ods graphics on;
proc iclifetest plots=(survival logsurv) data=BCS impute(seed=1234);
strata trt;
time (lTime, rTime);
run;
proc iclifetest data=BCS impute(seed=1234);
time (lTime, rTime);
test trt;
run;
ods trace off;
