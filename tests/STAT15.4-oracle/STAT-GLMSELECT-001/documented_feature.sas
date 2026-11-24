/* STAT-GLMSELECT-001: GLMSELECT — Data input, variable roles, and basic options
 * Source: S154 / Chapter 56 / `PROC GLMSELECT Statement` (PDF pp. 4324–4332); S154 / Chapter 56 / `BY Statement` (PDF p. 4332); S154 / Chapter 56 / `FREQ Statement` (PDF p. 4337); S154 / Chapter 56 / `WEIGHT Statement` (PDF pp. 4356–4357).
 * Discriminates: Verified default procedure context
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
quit;
