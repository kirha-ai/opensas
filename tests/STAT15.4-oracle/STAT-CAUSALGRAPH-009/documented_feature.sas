/* STAT-CAUSALGRAPH-009: CAUSALGRAPH — Limitations of the CAUSALGRAPH Procedure
 * Source: S154 / Chapter 37 / `Limitations of the CAUSALGRAPH Procedure` (PDF pp. 2329–2330).
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
