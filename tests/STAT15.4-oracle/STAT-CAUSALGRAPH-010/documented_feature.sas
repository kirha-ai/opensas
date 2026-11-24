/* STAT-CAUSALGRAPH-010: CAUSALGRAPH — Official examples and feature integration regression
 * Source: S154 / Chapter 37 / `Examples: CAUSALGRAPH Procedure` (PDF pp. 2332–2359).
 * Discriminates: Example 37.2: Searching Efficiently for an Adjustment Set
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc causalgraph method=adjustment maxlist=1 nosort;
model "Timm17HealthBehavior"
Age ==> Parity PFAS Education,
Parity ==> PrevBF Duration PFAS,
PrevBF ==> PFAS Duration,
PFAS ==> Duration,
Education ==> Duration HealthBehavior Employment,
HealthBehavior ==> PFAS Duration BMI Alcohol Smoking,
Employment ==> HealthBehavior Duration,
BMI Alcohol Smoking ==> Duration;
identify PFAS ==> Duration;
unmeasured PrevBF HealthBehavior;
run;

run; quit;
