/* STAT-SEQDESIGN-006: SEQDESIGN — Unified Family Methods / Haybittle-Peto Method / Whitehead Methods
 * Source: S154 / Chapter 110 / `Unified Family Methods` (PDF pp. 8980–8985); S154 / Chapter 110 / `Haybittle-Peto Method` (PDF p. 8985); S154 / Chapter 110 / `Whitehead Methods` (PDF pp. 8985–8989).
 * Discriminates: Example 110.5: Creating Designs Using Haybittle-Peto Methods
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
proc seqdesign altref=0.25
errspend
stopprob
plots=errspend
;
OneSidedPeto: design nstages=3
method=peto( z=3)
alt=upper stop=reject
alpha=0.05 beta=0.10;
run;
ods graphics on;
proc seqdesign altref=0.25
maxinfo=200
errspend
stopprob
plots=errspend
;
OneSidedPeto: design nstages=3
method=peto(z=3 2.5 2)
alt=upper stop=reject
boundarykey=none
;
run;
