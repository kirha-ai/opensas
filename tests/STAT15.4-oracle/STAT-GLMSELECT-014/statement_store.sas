/* STAT-GLMSELECT-014: GLMSELECT — STORE / Using the STORE
 * Source: S154 / Chapter 56 / `STORE Statement` (PDF p. 4356); S154 / Chapter 56 / `Using the STORE Statement` (PDF pp. 4374–4375).
 * Discriminates: Save the fitted item store and inspect it through PROC PLM SHOW ALL.
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

store out=work._oracle_store;
run;
quit;

proc plm restore=work._oracle_store; show all; run;
