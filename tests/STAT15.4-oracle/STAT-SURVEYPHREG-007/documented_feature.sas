/* STAT-SURVEYPHREG-007: SURVEYPHREG — Specifying the Sample Design / Taylor Series Linearization / Balanced Repeated Replication (BRR) Method
 * Source: S154 / Chapter 122 / `Specifying the Sample Design` (PDF pp. 10052–10054); S154 / Chapter 122 / `Taylor Series Linearization` (PDF pp. 10057–10058); S154 / Chapter 122 / `Balanced Repeated Replication (BRR) Method` (PDF pp. 10058–10061).
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
