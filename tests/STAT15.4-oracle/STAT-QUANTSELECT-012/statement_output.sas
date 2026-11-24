/* STAT-QUANTSELECT-012: QUANTSELECT — OUTPUT
 * Source: S154 / Chapter 104 / `OUTPUT Statement` (PDF pp. 8489–8490).
 * Discriminates: Create and print the procedure output data set using default statistic names.
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

output out=work._oracle_output;
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

proc print data=work._oracle_output(obs=10); run;
