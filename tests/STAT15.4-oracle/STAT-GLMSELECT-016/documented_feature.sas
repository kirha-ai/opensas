/* STAT-GLMSELECT-016: GLMSELECT — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 56 / `Displayed Output` (PDF pp. 4386–4390); S154 / Chapter 56 / `ODS Table Names` (PDF pp. 4390–4391).
 * Discriminates: Getting Started: GLMSELECT Procedure
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
proc contents varnum data=sashelp.baseball;
ods select position;
run;
ods graphics on;
proc glmselect data=sashelp.baseball plots=all seed=314159;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError
/ details=all stats=all;
run;
ods graphics off;
run;
quit;
ods trace off;
