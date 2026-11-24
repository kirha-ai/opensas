/* STAT-PSMATCH-007: PSMATCH — Matching Metrics / Matching Methods / Variable Balance Assessment
 * Source: S154 / Chapter 101 / `Matching Metrics` (PDF pp. 8245–8246); S154 / Chapter 101 / `Matching Methods` (PDF pp. 8246–8248); S154 / Chapter 101 / `Variable Balance Assessment` (PDF pp. 8250–8253).
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

data patients;
call streaminit(419);
do patientid=1 to 100;
gender=mod(patientid,2);
age=30+mod(patientid*7,45);
bmi=20+mod(patientid,12);
drug=rand('bernoulli',0.5);
output;
end;
run;
proc psmatch data=patients region=cs;
class drug gender;
psmodel drug(treated='1')=gender age bmi;
match method=greedy(k=1) distance=lps caliper=0.5;
assess lps var=(age bmi);
output out(obs=match)=matched matchid=matchid;
run;
proc print data=matched(obs=10) noobs;
run;
