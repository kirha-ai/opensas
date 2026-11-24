/* STAT-CAUSALMED-001: CAUSALMED — Data input, variable roles, and basic options
 * Source: S154 / Chapter 38 / `PROC CAUSALMED Statement` (PDF pp. 2373–2379); S154 / Chapter 38 / `BY Statement` (PDF pp. 2381–2382); S154 / Chapter 38 / `FREQ Statement` (PDF p. 2388); S154 / Chapter 38 / `WEIGHT Statement` (PDF pp. 2391–2392).
 * Discriminates: Verified default procedure context; explicit statements: WEIGHT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc causalmed data=sashelp.birthwgt decomp;
class LowBirthWgt Smoking Death AgeGroup Married Race
Drinking SomeCollege /descending;
mediator LowBirthWgt = Smoking;
model Death = LowBirthWgt | Smoking;
covar AgeGroup Married Race Drinking SomeCollege;
evaluate 'Low Birth-Weight' LowBirthWgt='Yes' / nodecomp;
evaluate 'Normal Birth-Weight' LowBirthWgt='No' / nodecomp;
run;
quit;
