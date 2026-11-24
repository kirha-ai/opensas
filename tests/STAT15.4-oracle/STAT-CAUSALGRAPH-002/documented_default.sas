/* STAT-CAUSALGRAPH-002: CAUSALGRAPH — Causal graph parsing and identification analysis
 * Source: S154 / Chapter 37 / `Getting Started: CAUSALGRAPH Procedure` (PDF pp. 2307–2310); S154 / Chapter 37 / `Overview: CAUSALGRAPH Procedure` (PDF pp. 2304–2307).
 * Discriminates: Documented default analysis with explicit complete public or synthetic inputs
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
quit;
