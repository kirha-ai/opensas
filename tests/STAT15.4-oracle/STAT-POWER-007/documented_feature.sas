/* STAT-POWER-007: POWER — TWOSAMPLESURVIVAL / TWOSAMPLEWILCOXON / Overview of Power Concepts
 * Source: S154 / Chapter 96 / `TWOSAMPLESURVIVAL Statement` (PDF pp. 7830–7842); S154 / Chapter 96 / `TWOSAMPLEWILCOXON Statement` (PDF pp. 7842–7847); S154 / Chapter 96 / `Overview of Power Concepts` (PDF pp. 7847–7848).
 * Discriminates: Example 96.6: Comparing Two Survival Curves; explicit statements: TWOSAMPLESURVIVAL
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc power;
twosamplesurvival test=logrank
curve("Standard") = 5 : 0.5
curve("Proposed") = (1 to 5 by 1):(0.95 0.9 0.75 0.7 0.6)
groupsurvival = "Standard" | "Proposed"
accrualtime = 2
followuptime = 3
groupmedlosstimes = 10 | 20 5
power = 0.8
npergroup = .;
run;
