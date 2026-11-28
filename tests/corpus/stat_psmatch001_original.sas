/* expect-rc: 1
 * Unchanged STAT-PSMATCH-001 oracle program (permanent replay); expected words are the SAS 9.4 reference listing tokens (PROC PRINT column layout is STAT-PRINT-001).
 * STAT-PSMATCH-001: PSMATCH — Data input, variable roles, and basic options
 * Source: S154 / Chapter 101 / `PROC PSMATCH Statement` (PDF pp. 8214–8217); S154 / Chapter 101 / `BY Statement` (PDF pp. 8222–8223); S154 / Chapter 101 / `CLASS Statement` (PDF p. 8223); S154 / Chapter 101 / `FREQ Statement` (PDF p. 8223); S154 / Chapter 101 / `ID Statement` (PDF p. 8223); S154 / Chapter 101 / `STRATA Statement` (PDF pp. 8234–8235); S154 / Chapter 101 / `Weighting after Stratification` (PDF pp. 8243–8244); S154 / Chapter 101 / `Weighting after Matching` (PDF pp. 8248–8250).
 * Discriminates: Verified default procedure context; explicit statements: CLASS
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
