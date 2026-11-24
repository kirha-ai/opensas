/* STAT-SEQDESIGN-003: SEQDESIGN — DESIGN / SAMPLESIZE / Fixed-Sample Clinical Trials
 * Source: S154 / Chapter 110 / `DESIGN Statement` (PDF pp. 8943–8949); S154 / Chapter 110 / `SAMPLESIZE Statement` (PDF pp. 8949–8959); S154 / Chapter 110 / `Fixed-Sample Clinical Trials` (PDF pp. 8959–8963).
 * Discriminates: Example 110.1: Creating Fixed-Sample Designs; explicit statements: DESIGN, SAMPLESIZE
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
proc seqdesign pss
;
OneSidedFixedSample: design nstages=1
alt=upper
alpha=0.025 beta=0.10
;
samplesize model=onesamplemean(mean=0.25);
run;
ods graphics on;
proc seqdesign altref=1.2
pss
;
TwoSidedFixedSample: design nstages=1
alt=twosided
alpha=0.05 beta=0.10
;
samplesize model=twosamplemean(stddev=2 weight=2);
run;
