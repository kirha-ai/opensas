/* STAT-POWER-004: POWER — MULTREG / ONECORR / ONESAMPLEFREQ
 * Source: S154 / Chapter 96 / `MULTREG Statement` (PDF pp. 7763–7768); S154 / Chapter 96 / `ONECORR Statement` (PDF pp. 7768–7772); S154 / Chapter 96 / `ONESAMPLEFREQ Statement` (PDF pp. 7772–7780).
 * Discriminates: Example 96.5: Multiple Regression and Correlation; explicit statements: MULTREG, ONECORR
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
proc power;
multreg
model = random
nfullpredictors = 7
ntestpredictors = 1
partialcorr = 0.35
ntotal = 100
power = .;
plot x=n min=50 max=150;
run;
ods graphics off;
proc power;
onecorr dist=fisherz
npvars = 6
corr = 0.35
nullcorr = 0.2
sides = 1
ntotal = 100
power = .;
run;
proc power;
onecorr dist=fisherz
npvars = 6
corr = 0.35
nullcorr = 0.2
sides = 1
ntotal = .
power = 0.85 0.95;
run;
