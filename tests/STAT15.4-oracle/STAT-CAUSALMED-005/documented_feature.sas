/* STAT-CAUSALMED-005: CAUSALMED — STD / Causal Mediation Effects: Definitions, Assumptions, and Identification / Evaluating Causal Mediation Effects
 * Source: S154 / Chapter 38 / `STD Statement` (PDF pp. 2390–2391); S154 / Chapter 38 / `Causal Mediation Effects: Definitions, Assumptions, and Identification` (PDF pp. 2392–2400); S154 / Chapter 38 / `Evaluating Causal Mediation Effects` (PDF pp. 2400–2406).
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
