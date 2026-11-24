/* STAT-SURVEYLOGISTIC-020: SURVEYLOGISTIC — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 120 / `Displayed Output` (PDF pp. 9876–9881); S154 / Chapter 120 / `ODS Table Names` (PDF pp. 9881–9882).
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

ods trace on;
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
ods trace off;
