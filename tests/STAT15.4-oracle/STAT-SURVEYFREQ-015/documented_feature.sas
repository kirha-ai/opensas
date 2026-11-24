/* STAT-SURVEYFREQ-015: SURVEYFREQ — Rao-Scott Chi-Square Test / Rao-Scott Likelihood Ratio Chi-Square Test
 * Source: S154 / Chapter 118 / `Rao-Scott Chi-Square Test` (PDF pp. 9661–9667); S154 / Chapter 118 / `Rao-Scott Likelihood Ratio Chi-Square Test` (PDF pp. 9667–9668).
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
