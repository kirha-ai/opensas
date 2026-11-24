/* STAT-SURVEYFREQ-001: SURVEYFREQ — Data input, variable roles, and basic options
 * Source: S154 / Chapter 118 / `PROC SURVEYFREQ Statement` (PDF pp. 9587–9598); S154 / Chapter 118 / `BY Statement` (PDF p. 9598); S154 / Chapter 118 / `CLUSTER Statement` (PDF pp. 9598–9599); S154 / Chapter 118 / `REPWEIGHTS Statement` (PDF pp. 9599–9601); S154 / Chapter 118 / `STRATA Statement` (PDF pp. 9601–9602); S154 / Chapter 118 / `WEIGHT Statement` (PDF pp. 9626–9627); S154 / Chapter 118 / `Missing Values` (PDF pp. 9630–9632).
 * Discriminates: Verified default procedure context; explicit statements: CLUSTER, STRATA, WEIGHT
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
do state=1 to 2;
do school=1 to 4;
do id=1 to 6;
response=1+mod(id+school,3);
schooltype=1+mod(school,2);
samplingweight=2+state+school/10;
output;
end;
end;
end;
run;
proc surveyfreq data=survey;
strata state;
cluster school;
weight samplingweight;
tables schooltype*response / row chisq;
run;
