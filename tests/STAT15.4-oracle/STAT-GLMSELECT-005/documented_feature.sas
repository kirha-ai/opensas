/* STAT-GLMSELECT-005: GLMSELECT — Backward Elimination (BACKWARD) / Least Angle Regression (LAR) / Macro Variables Containing Selected Models
 * Source: S154 / Chapter 56 / `Backward Elimination (BACKWARD)` (PDF pp. 4360–4361); S154 / Chapter 56 / `Least Angle Regression (LAR)` (PDF pp. 4362–4363); S154 / Chapter 56 / `Macro Variables Containing Selected Models` (PDF pp. 4372–4374).
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
