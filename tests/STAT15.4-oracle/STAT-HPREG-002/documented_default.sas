/* STAT-HPREG-002: HPREG — High-performance linear regression and model selection
 * Source: S154 / Chapter 67 / `Getting Started: HPREG Procedure` (PDF pp. 5022–5028); S154 / Chapter 67 / `Overview: HPREG Procedure` (PDF pp. 5020–5022).
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
