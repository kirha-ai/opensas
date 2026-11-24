/* STAT-SURVEYLOGISTIC-014: SURVEYLOGISTIC — Testing Global Null Hypothesis: BETA=0 / Wald Confidence Intervals for Parameters / Testing Linear Hypotheses about the Regression Coefficients
 * Source: S154 / Chapter 120 / `Testing Global Null Hypothesis: BETA=0` (PDF pp. 9865–9868); S154 / Chapter 120 / `Wald Confidence Intervals for Parameters` (PDF p. 9868); S154 / Chapter 120 / `Testing Linear Hypotheses about the Regression Coefficients` (PDF pp. 9868–9869).
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

data survey;
call streaminit(722);
do stratum=1 to 2;
do cluster=1 to 4;
do id=1 to 12;
age=20+mod(id*7+cluster,45);
event=rand('bernoulli',0.3);
weight=2+stratum+cluster/10;
output;
end;
end;
end;
run;
proc surveylogistic data=survey;
strata stratum;
cluster cluster;
weight weight;
model event(event='1')=age;
run;
