/* STAT-BGLIMM-010: BGLIMM — Initial Values of the Markov Chains / Autocall Macros for Postprocessing
 * Source: S154 / Chapter 31 / `Initial Values of the Markov Chains` (PDF pp. 1322–1323); S154 / Chapter 31 / `Autocall Macros for Postprocessing` (PDF pp. 1323–1325).
 * Discriminates: Getting Started: BGLIMM Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data MultiCenter;
input Center Group$ N SideEffect @@;
datalines;
1 A 32 14 1 B 33 18
2 A 30 4 2 B 28 8
3 A 23 14 3 B 24 9
4 A 22 7 4 B 22 10
5 A 20 6 5 B 21 12
6 A 19 1 6 B 20 3
7 A 17 2 7 B 17 6
8 A 16 7 8 B 15 9
9 A 13 1 9 B 14 5
10 A 13 3 10 B 13 1
11 A 11 1 11 B 12 2
12 A 10 1 12 B 9 0
13 A 9 2 13 B 9 6
14 A 8 1 14 B 8 1
15 A 7 1 15 B 8 0
;
ods graphics on;
proc bglimm data=MultiCenter nmc=1000 thin=2 seed=976352
plots=all nbi=200;
class Center Group;
model SideEffect/N = Group / noint;
random int / subject = Center;
run;
proc bglimm data=MultiCenter nmc=1000 thin=2 seed=976352
outpost=CenterOut nbi=200;
class Center Group;
model SideEffect/N = Group / noint;
random int / subject=Center monitor;
estimate "log OR" group 1 -1;
run;
data prob;
set CenterOut;
pDiff = logistic(group_a) - logistic(group_b);
run;
%sumint(data=prob, var=pDiff)
proc sgplot data=prob noautolegend;
run;
