/* STAT-HPREG-010: HPREG — OUTPUT / Output Data Set
 * Source: S154 / Chapter 67 / `OUTPUT Statement` (PDF pp. 5033–5035); S154 / Chapter 67 / `Output Data Set` (PDF p. 5045).
 * Discriminates: Getting Started: HPREG Procedure; explicit statements: OUTPUT
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
