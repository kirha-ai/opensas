/* STAT-SURVEYPHREG-006: SURVEYPHREG — Left-Truncation of Failure Times / The Multiplicative Hazards Model / Firth's Modification for Maximum Likelihood Estimation
 * Source: S154 / Chapter 122 / `Left-Truncation of Failure Times` (PDF p. 10049); S154 / Chapter 122 / `The Multiplicative Hazards Model` (PDF pp. 10049–10050); S154 / Chapter 122 / `Firth's Modification for Maximum Likelihood Estimation` (PDF pp. 10050–10052).
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
time=1+rand('exponential')*10;
status=(mod(id,4) ne 0);
weight=2+stratum+cluster/10;
output;
end;
end;
end;
run;
proc surveyphreg data=survey;
strata stratum;
cluster cluster;
weight weight;
model time*status(0)=age;
run;
