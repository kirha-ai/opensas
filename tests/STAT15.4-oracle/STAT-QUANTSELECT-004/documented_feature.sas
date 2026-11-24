/* STAT-QUANTSELECT-004: QUANTSELECT — Quasi-Likelihood Information Criteria / Quantile Process Regression / Observation Quantile Level
 * Source: S154 / Chapter 104 / `Quasi-Likelihood Information Criteria` (PDF pp. 8491–8492); S154 / Chapter 104 / `Quantile Process Regression` (PDF pp. 8494–8495); S154 / Chapter 104 / `Observation Quantile Level` (PDF p. 8495).
 * Discriminates: Getting Started: QUANTSELECT Procedure
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
proc quantselect data=sashelp.baseball;
class Div;
model Salary = nAtBat nHits nHome nRuns nRBI nBB yrMajor crAtBat
crHits crHome crRuns crRbi crBB nAssts nError nOuts
Div
/ selection=lasso(adaptive stop=aic choose=sbc sh=7);
run;
proc quantselect data=sashelp.baseball;
class Div;
model Salary = nAtBat nHits nHome nRuns nRBI nBB yrMajor crAtBat
crHits crHome crRuns crRbi crBB nAssts nError nOuts
Div
/ quantiles=0.1 0.9 selection=lasso(adaptive stop=aic choose=sbc sh=7);
run;
ods graphics on;
proc quantselect data=sashelp.baseball plots=all;
class Div;
model Salary = nAtBat nHits nHome nRuns nRBI nBB yrMajor crAtBat
crHits crHome crRuns crRbi crBB nAssts nError nOuts
Div
/ quantiles=0.1 selection=lasso(adaptive stop=aic choose=sbc sh=7);
run;
