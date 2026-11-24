/* STAT-GLMSELECT-007: GLMSELECT — MODELAVERAGE / PARTITION / Forward Selection (FORWARD)
 * Source: S154 / Chapter 56 / `MODELAVERAGE Statement` (PDF pp. 4348–4352); S154 / Chapter 56 / `PARTITION Statement` (PDF pp. 4354–4355); S154 / Chapter 56 / `Forward Selection (FORWARD)` (PDF pp. 4357–4360).
 * Discriminates: Example 56.1: Modeling Baseball Salaries Using Performance Statistics; explicit statements: PARTITION
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
proc glmselect data=sashelp.baseball plot=CriterionPanel seed=314159;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError
/ selection=stepwise(select=SL) stats=all;
run;
proc glmselect data=sashelp.baseball seed=314159;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError
/ selection=stepwise(select=SL choose=PRESS);
run;
proc glmselect data=sashelp.baseball plot=Coefficients seed=314159;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError
/ selection=stepwise(select=SL stop=PRESS);
run;
proc glmselect data=sashelp.baseball plot=Candidates seed=314159;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError
/ selection=stepwise(select=CV drop=competitive)
cvMethod=split(5);
run;
proc glmselect data=sashelp.baseball plots=(CriterionPanel ASE) seed=1;
partition fraction(validate=0.3 test=0.2);
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError
/ selection=forward(choose=validate stop=10);
run;
proc glmselect data=sashelp.baseball plot=CriterionPanel  seed=314159;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError
/ selection=LASSO(choose=CP steps=20);
run;
ods graphics off;
run;
quit;
