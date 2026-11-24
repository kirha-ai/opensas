/* STAT-HPSPLIT-004: HPSPLIT — RULES / Building a Decision Tree / Splitting Criteria
 * Source: S154 / Chapter 68 / `RULES Statement` (PDF pp. 5096–5097); S154 / Chapter 68 / `Building a Decision Tree` (PDF pp. 5097–5100); S154 / Chapter 68 / `Splitting Criteria` (PDF pp. 5100–5103).
 * Discriminates: Example 68.3: Creating a Regression Tree
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
