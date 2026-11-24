/* STAT-PROBIT-002: PROBIT — Probit and related discrete response model estimation
 * Source: S154 / Chapter 100 / `Getting Started: PROBIT Procedure` (PDF pp. 8095–8099); S154 / Chapter 100 / `Overview: PROBIT Procedure` (PDF pp. 8094–8095).
 * Discriminates: Getting Started: PROBIT Procedure
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
proc probit data=study log10 optc plots=(predpplot ippplot);
model respond/number=dose;
output out=new p=p_hat;
run;
