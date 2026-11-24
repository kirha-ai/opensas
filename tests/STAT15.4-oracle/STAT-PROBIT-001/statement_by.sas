/* STAT-PROBIT-001: PROBIT — Data input, variable roles, and basic options
 * Source: S154 / Chapter 100 / `PROC PROBIT Statement` (PDF pp. 8100–8105); S154 / Chapter 100 / `BY Statement` (PDF pp. 8105–8106); S154 / Chapter 100 / `WEIGHT Statement` (PDF p. 8120); S154 / Chapter 100 / `Missing Values` (PDF p. 8120).
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

data study;
input Dose Respond @@;
Number = 15;
datalines;
0 3 1.1 4 1.3 4 2.0 3 2.2 5 2.8 4
3.7 5 3.9 9 4.4 8 4.8 11 5.9 12 6.8 13
;
ods graphics on;
data _oracle_input; set study; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc probit data=_oracle_input log10 optc plots=(predpplot ippplot);
by _oracle_by;
model respond/number=dose;
output out=new p=p_hat;
run;
