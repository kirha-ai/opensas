/* STAT-CAUSALMED-009: CAUSALMED — Official examples and feature integration regression
 * Source: S154 / Chapter 38 / `Examples: CAUSALMED Procedure` (PDF pp. 2409–2426).
 * Discriminates: Example 38.3: Smoking Effect on Infant Mortality
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc print data=sashelp.birthwgt(obs=10);
run;
proc causalmed data=sashelp.birthwgt decomp;
class LowBirthWgt Smoking Death AgeGroup Married Race
Drinking SomeCollege /descending;
mediator LowBirthWgt = Smoking;
model Death = LowBirthWgt | Smoking;
covar AgeGroup Married Race Drinking SomeCollege;
evaluate 'Low Birth-Weight' LowBirthWgt='Yes' / nodecomp;
evaluate 'Normal Birth-Weight' LowBirthWgt='No' / nodecomp;
run;
