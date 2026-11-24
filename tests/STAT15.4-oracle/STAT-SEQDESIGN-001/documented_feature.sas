/* STAT-SEQDESIGN-001: SEQDESIGN — Data input, variable roles, and basic options
 * Source: S154 / Chapter 110 / `PROC SEQDESIGN Statement` (PDF pp. 8939–8943).
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

ods graphics on;
proc seqdesign altref=-10
plots=boundary(hscale=samplesize)
;
TwoSidedOBrienFleming: design nstages=4
method=obf
;
samplesize model=twosamplemean(stddev=20);
ods output Boundary=Bnd_LDL;
run;
