/* STAT-CAUSALTRT-010: CAUSALTRT — ODS Graphics
 * Source: S154 / Chapter 39 / `ODS Graphics` (PDF pp. 2474–2475).
 * Discriminates: Getting Started: CAUSALTRT Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;
ods trace on;
data drugs; call streaminit(193); length Drug $6 Gender $1 Diabetes2 $3; do ID=1 to 200; Age=20+mod(id*7,45); BMI=20+mod(id,12); if mod(id,2) then Gender='F'; else Gender='M'; if rand('bernoulli',0.5) then Drug='Drug_A'; else Drug='Drug_B'; if rand('bernoulli',0.3+0.1*(Drug='Drug_A')) then Diabetes2='Yes'; else Diabetes2='No'; output; end; run;

proc causaltrt data=drugs method=ipwr ppsmodel;
class Gender;
psmodel Drug(ref='Drug_A') = Age Gender BMI;
model Diabetes2(ref='No') / dist = bin;
run;
proc causaltrt data=drugs method=aipw;
class Gender;
psmodel Drug(ref='Drug_A') = Age Gender BMI;
model Diabetes2(ref='No') = Age Gender BMI / dist = bin;
run;
ods trace off;
ods trace off;
ods graphics off;
