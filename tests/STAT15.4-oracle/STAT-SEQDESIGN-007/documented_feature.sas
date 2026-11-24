/* STAT-SEQDESIGN-007: SEQDESIGN — Error Spending Methods / Acceptance (beta) Boundary / Boundary Adjustments for Overlapping Lower and Upper beta Boundaries
 * Source: S154 / Chapter 110 / `Error Spending Methods` (PDF pp. 8989–8991); S154 / Chapter 110 / `Acceptance (beta) Boundary` (PDF pp. 8991–8994); S154 / Chapter 110 / `Boundary Adjustments for Overlapping Lower and Upper beta Boundaries` (PDF pp. 8994–8995).
 * Discriminates: Example 110.10: Creating Two-Sided Error Spending Designs with and without Overlapping Lower and Upper beta Boundaries
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
proc seqdesign altref=0.2 errspend;
design nstages=3
method=errfuncpow
alt=twosided stop=accept
betaoverlap=noadjust
beta=0.09
;
run;
ods graphics on;
proc seqdesign altref=0.2 errspend;
design nstages=3
method=errfuncpow
alt=twosided
stop=accept
betaoverlap=adjust
beta=0.09
;
run;
ods graphics off;
