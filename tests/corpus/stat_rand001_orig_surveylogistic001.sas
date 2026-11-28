/* STAT-RAND-001: the STAT-SURVEYLOGISTIC-001 oracle program, unchanged below this comment;
 * its data come from seeded RAND draws after CALL STREAMINIT. The expected
 * listing is the SAS 9.4 reference listing of that program.
 */
/* STAT-SURVEYLOGISTIC-001: SURVEYLOGISTIC — Data input, variable roles, and basic options
 * Source: S154 / Chapter 120 / `PROC SURVEYLOGISTIC Statement` (PDF pp. 9803–9811); S154 / Chapter 120 / `BY Statement` (PDF pp. 9811–9812); S154 / Chapter 120 / `CLUSTER Statement` (PDF p. 9814); S154 / Chapter 120 / `FREQ Statement` (PDF p. 9820); S154 / Chapter 120 / `REPWEIGHTS Statement` (PDF pp. 9834–9836); S154 / Chapter 120 / `STRATA Statement` (PDF p. 9837); S154 / Chapter 120 / `WEIGHT Statement` (PDF p. 9839); S154 / Chapter 120 / `Missing Values` (PDF pp. 9839–9840).
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
