/* STAT-GLMSELECT-010: GLMSELECT — Criteria Used in Model Selection Methods / Model Averaging / Using Validation and Test Data
 * Source: S154 / Chapter 56 / `Criteria Used in Model Selection Methods` (PDF pp. 4368–4370); S154 / Chapter 56 / `Model Averaging` (PDF pp. 4376–4377); S154 / Chapter 56 / `Using Validation and Test Data` (PDF pp. 4377–4379).
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
