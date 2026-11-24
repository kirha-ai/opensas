/* STAT-SURVEYFREQ-002: SURVEYFREQ — Weighted frequency and proportion inference for complex surveys
 * Source: S154 / Chapter 118 / `Getting Started: SURVEYFREQ Procedure` (PDF pp. 9579–9587); S154 / Chapter 118 / `Overview: SURVEYFREQ Procedure` (PDF pp. 9578–9579).
 * Discriminates: Small synthetic/public-input default model adapted to the documented Getting Started procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data survey; do state=1 to 2; do school=1 to 4; do id=1 to 6; response=1+mod(id+school,3); schooltype=1+mod(school,2); samplingweight=2+state+school/10; output; end; end; end; run;
proc surveyfreq data=survey; strata state; cluster school; weight samplingweight; tables schooltype*response / row chisq; run;
