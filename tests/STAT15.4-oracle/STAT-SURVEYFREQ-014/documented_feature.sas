/* STAT-SURVEYFREQ-014: SURVEYFREQ — Discordant Proportion Difference / Kappa Coefficients
 * Source: S154 / Chapter 118 / `Discordant Proportion Difference` (PDF pp. 9657–9658); S154 / Chapter 118 / `Kappa Coefficients` (PDF pp. 9658–9661).
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
