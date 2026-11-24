/* STAT-CAUSALGRAPH-006: CAUSALGRAPH — ODS Table Names
 * Source: S154 / Chapter 37 / `ODS Table Names` (PDF pp. 2331–2332).
 * Discriminates: Getting Started: CAUSALGRAPH Procedure
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
proc causalgraph;
model "Timm17TwoLatent"
Age ==> Parity PFAS Education,
Parity ==> PrevBF Duration PFAS,
PrevBF ==> PFAS Duration,
PFAS ==> Duration,
Education ==> Duration Employment PFAS BMI Alcohol Smoking,
Employment ==> Duration PFAS BMI Alcohol Smoking,
BMI Alcohol Smoking ==> Duration;
identify PFAS ==> Duration;
unmeasured Alcohol Smoking;
run;

run; quit;

ods trace off;
