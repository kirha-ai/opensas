/* STAT-CALIS-026: CALIS — Case-Level Residuals, Outliers, Leverage Observations, and Residual Diagnostics
 * Source: S154 / Chapter 33 / `Case-Level Residuals, Outliers, Leverage Observations, and Residual Diagnostics` (PDF pp. 1789–1793).
 * Discriminates: Example 33.14: Residual Diagnostics and Robust Estimation
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data mardia;
call streaminit(314159);
do id=1 to 120;
 fact=rand('normal');
 mechanics=60+8*fact+4*rand('normal');
 vector=65+7*fact+4*rand('normal');
 algebra=63+9*fact+4*rand('normal');
 analysis=64+6*fact+4*rand('normal');
 statistics=66+8*fact+4*rand('normal');
 if id=120 then mechanics=mechanics+30;
 output;
end;
drop fact id;
run;
ods graphics on;
proc calis data=mardia residual plots=caseresid;
path
fact1 ===> mechanics vector algebra analysis statistics = 1. ;
run;
ods graphics off;
ods graphics on;
proc calis data=mardia residual robust plots=caseresid pcorr;
path
fact1 ===> mechanics vector algebra analysis statistics = 1. ;
run;
ods graphics off;
proc calis data=mardia robust=sat pcorr;
path
fact1 ===> mechanics vector algebra analysis statistics = 1. ;
run;
