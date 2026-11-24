/* STAT-HPREG-009: HPREG — CODE
 * Source: S154 / Chapter 67 / `CODE Statement` (PDF pp. 5030–5031).
 * Discriminates: Generate DATA step scoring code, execute it against the input rows, and print the scored data.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

filename _orcode "%sysfunc(pathname(work))/_oracle_score.sas";


proc contents varnum data=sashelp.baseball;
ods select position;
run;
proc hpreg data=sashelp.baseball;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError;
selection method=stepwise;

code file="%sysfunc(pathname(work))/_oracle_score.sas";
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

data _oracle_scored; set sashelp.baseball;
%include _orcode;
run;
proc print data=_oracle_scored(obs=10); run;
