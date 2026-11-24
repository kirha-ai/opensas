/* STAT-HPREG-011: HPREG — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 67 / `Displayed Output` (PDF pp. 5046–5050); S154 / Chapter 67 / `ODS Table Names` (PDF pp. 5050–5052).
 * Discriminates: Getting Started: HPREG Procedure
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
proc hpreg data=sashelp.baseball;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError;
selection method=stepwise;
run;
proc hpreg data=sashelp.baseball;
id name;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError / vif clb;
selection method=stepwise;
output out=baseballOut p=predictedLogSalary r h cookd rstudent;
run;
proc print data=baseballOut(obs=5);
run;
ods trace off;
