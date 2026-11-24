/* STAT-HPREG-001: HPREG — Data input, variable roles, and basic options
 * Source: S154 / Chapter 67 / `PROC HPREG Statement` (PDF pp. 5028–5029); S154 / Chapter 67 / `BY Statement` (PDF pp. 5029–5030); S154 / Chapter 67 / `FREQ Statement` (PDF p. 5031); S154 / Chapter 67 / `ID Statement` (PDF p. 5031); S154 / Chapter 67 / `WEIGHT Statement` (PDF p. 5038).
 * Discriminates: Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results.
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
data _oracle_input; set sashelp.baseball; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc hpreg data=_oracle_input;
by _oracle_by;
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
