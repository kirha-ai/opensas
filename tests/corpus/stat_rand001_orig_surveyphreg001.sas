/* STAT-RAND-001: the STAT-SURVEYPHREG-001 oracle program, unchanged below this comment;
 * its data come from seeded RAND draws after CALL STREAMINIT. The expected
 * listing is the SAS 9.4 reference listing of that program.
 */
/* STAT-SURVEYPHREG-001: SURVEYPHREG — Data input, variable roles, and basic options
 * Source: S154 / Chapter 122 / `PROC SURVEYPHREG Statement` (PDF pp. 10010–10018); S154 / Chapter 122 / `BY Statement` (PDF pp. 10018–10019); S154 / Chapter 122 / `CLUSTER Statement` (PDF pp. 10021–10022); S154 / Chapter 122 / `FREQ Statement` (PDF pp. 10024–10025); S154 / Chapter 122 / `REPWEIGHTS Statement` (PDF pp. 10038–10040); S154 / Chapter 122 / `STRATA Statement` (PDF pp. 10040–10041); S154 / Chapter 122 / `WEIGHT Statement` (PDF pp. 10041–10042); S154 / Chapter 122 / `Missing Values` (PDF pp. 10054–10057).
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
