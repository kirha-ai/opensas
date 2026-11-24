/* STAT-SURVEYLOGISTIC-009: SURVEYLOGISTIC — Taylor Series (Linearization) / Balanced Repeated Replication (BRR) Method / Fay's BRR Method
 * Source: S154 / Chapter 120 / `Taylor Series (Linearization)` (PDF pp. 9855–9857); S154 / Chapter 120 / `Balanced Repeated Replication (BRR) Method` (PDF pp. 9859–9860); S154 / Chapter 120 / `Fay's BRR Method` (PDF pp. 9860–9861).
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
