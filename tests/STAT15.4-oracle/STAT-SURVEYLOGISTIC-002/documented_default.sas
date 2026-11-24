/* STAT-SURVEYLOGISTIC-002: SURVEYLOGISTIC — Logistic regression for complex survey data
 * Source: S154 / Chapter 120 / `Getting Started: SURVEYLOGISTIC Procedure` (PDF pp. 9798–9802); S154 / Chapter 120 / `Overview: SURVEYLOGISTIC Procedure` (PDF pp. 9796–9798).
 * Discriminates: Documented default analysis with explicit complete public or synthetic inputs
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data survey; call streaminit(722); do stratum=1 to 2; do cluster=1 to 4; do id=1 to 12; age=20+mod(id*7+cluster,45); event=rand('bernoulli',0.3); weight=2+stratum+cluster/10; output; end; end; end; run;
proc surveylogistic data=survey; strata stratum; cluster cluster; weight weight; model event(event='1')=age; run;
