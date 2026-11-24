/* STAT-SEQDESIGN-013: SEQDESIGN — Graphics Output / ODS Graphics
 * Source: S154 / Chapter 110 / `Graphics Output` (PDF pp. 9027–9029); S154 / Chapter 110 / `ODS Graphics` (PDF p. 9029).
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
ods trace on;
ods trace on;
ods graphics on;
proc seqdesign altref=0.4
plots=all
;
TwoSidedPocock: design nstages=4 method=poc;
TwoSidedOBrienFleming: design nstages=4 method=obf;
run;
ods trace off;
ods trace off;
ods graphics off;
