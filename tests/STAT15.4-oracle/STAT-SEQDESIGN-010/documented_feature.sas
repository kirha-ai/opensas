/* STAT-SEQDESIGN-010: SEQDESIGN — Aspects of Group Sequential Designs / Summary of Methods in Group Sequential Designs
 * Source: S154 / Chapter 110 / `Aspects of Group Sequential Designs` (PDF pp. 9018–9021); S154 / Chapter 110 / `Summary of Methods in Group Sequential Designs` (PDF pp. 9021–9023).
 * Discriminates: Example 110.4: Generating Graphics Display for Sequential Designs
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
proc seqdesign altref=0.4
plots=all
;
TwoSidedPocock: design nstages=4 method=poc;
TwoSidedOBrienFleming: design nstages=4 method=obf;
run;
