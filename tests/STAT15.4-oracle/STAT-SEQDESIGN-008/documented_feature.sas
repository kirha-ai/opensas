/* STAT-SEQDESIGN-008: SEQDESIGN — Specified and Derived Parameters / Applicable Boundary Keys / Sample Size Computation
 * Source: S154 / Chapter 110 / `Specified and Derived Parameters` (PDF pp. 8995–8996); S154 / Chapter 110 / `Applicable Boundary Keys` (PDF pp. 8996–8997); S154 / Chapter 110 / `Sample Size Computation` (PDF pp. 8997–9005).
 * Discriminates: Example 110.14: Computing Sample Size for Survival Data That Have Uniform Accrual
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc seqdesign;
ErrorSpend: design nstages=4 method=errfuncobf
;
samplesize model=twosamplesurvival
( nullhazard=0.03466 hazard=0.01733
accrual=uniform accrate=15);
run;
proc seqdesign;
ErrorSpend: design nstages=4 method=errfuncobf
;
samplesize model(ceiladjdesign=include)=twosamplesurvival
( nullhazard=0.03466 hazard=0.01733
accrual=uniform accrate=15 acctime=18
ceiling=time);
run;
