/* STAT-HPSPLIT-001: HPSPLIT — Data input, variable roles, and basic options
 * Source: S154 / Chapter 68 / `PROC HPSPLIT Statement` (PDF pp. 5079–5088); S154 / Chapter 68 / `ID Statement` (PDF p. 5092); S154 / Chapter 68 / `WEIGHT Statement` (PDF p. 5097); S154 / Chapter 68 / `Handling Missing Values` (PDF pp. 5109–5110).
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

ods graphics on;
proc hpsplit data=sashelp.baseball seed=123;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError;
output out=hpsplout;
run;
