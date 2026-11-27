/* expect-rc: 0; D-009: clean run */
/* STAT-COMMON-001: Statistical procedure execution and the 15.4 option contract
 * Source: S154 / Chapter 3 / `Introduction` (PDF pp. 27–36); S154 / Chapter 2 / `What's New in SAS/STAT 15.4` (PDF pp. 25–26); S154 / Chapter 1 / `Procedures by Category` (PDF pp. 13–24).
 * Discriminates: Runtime version, PROC dispatch, RUN/QUIT and default result objects
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
data runtime; length version $64; version=symget('sysvlong4'); run;
proc print data=runtime noobs; run;
proc reg data=sample; model y=x z; run; quit;
