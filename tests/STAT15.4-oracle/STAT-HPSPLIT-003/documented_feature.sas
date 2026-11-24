/* STAT-HPSPLIT-003: HPSPLIT — CLASS / MODEL
 * Source: S154 / Chapter 68 / `CLASS Statement` (PDF pp. 5088–5089); S154 / Chapter 68 / `MODEL Statement` (PDF pp. 5092–5093).
 * Discriminates: Example 68.3: Creating a Regression Tree; explicit statements: CLASS, MODEL
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
