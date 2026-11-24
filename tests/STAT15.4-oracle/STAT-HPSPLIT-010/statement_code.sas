/* STAT-HPSPLIT-010: HPSPLIT — CODE / Scoring
 * Source: S154 / Chapter 68 / `CODE Statement` (PDF pp. 5089–5090); S154 / Chapter 68 / `Scoring` (PDF pp. 5110–5111).
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


ods graphics on;
proc hpsplit data=sashelp.baseball seed=123;
class league division;
model logSalary = nAtBat nHits nHome nRuns nRBI nBB
yrMajor crAtBat crHits crHome crRuns crRbi
crBB league division nOuts nAssts nError;
output out=hpsplout;

code file="%sysfunc(pathname(work))/_oracle_score.sas";
run;

data _oracle_scored; set sashelp.baseball;
%include _orcode;
run;
proc print data=_oracle_scored(obs=10); run;
