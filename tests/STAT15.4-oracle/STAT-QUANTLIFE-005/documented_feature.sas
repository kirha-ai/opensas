/* STAT-QUANTLIFE-005: QUANTLIFE — Nelson-Aalen-Type Estimator for Censored Quantile Regression / Relationship of Quantile Function and Survival Function
 * Source: S154 / Chapter 102 / `Nelson-Aalen-Type Estimator for Censored Quantile Regression` (PDF pp. 8340–8341); S154 / Chapter 102 / `Relationship of Quantile Function and Survival Function` (PDF pp. 8341–8342).
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

data survival;
call streaminit(518);
do id=1 to 80;
drug=mod(id,2);
age=25+mod(id*7,40);
time=exp(2+0.25*drug+0.008*age+rand('normal')*0.4);
status=(mod(id,5) ne 0);
output;
end;
run;
proc quantlife data=survival seed=1268;
class drug;
model time*status(0)=drug age / quantile=0.5;
run;
