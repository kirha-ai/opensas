/* STAT-GLMSELECT-003: GLMSELECT — CLASS / EFFECT / MODEL
 * Source: S154 / Chapter 56 / `CLASS Statement` (PDF pp. 4332–4336); S154 / Chapter 56 / `EFFECT Statement` (PDF pp. 4336–4337); S154 / Chapter 56 / `MODEL Statement` (PDF pp. 4337–4348).
 * Discriminates: Getting Started: GLMSELECT Procedure; explicit statements: CLASS, MODEL
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
