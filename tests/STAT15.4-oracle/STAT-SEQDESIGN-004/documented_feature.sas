/* STAT-SEQDESIGN-004: SEQDESIGN — One-Sided Fixed-Sample Tests in Clinical Trials / Two-Sided Fixed-Sample Tests in Clinical Trials / Group Sequential Methods
 * Source: S154 / Chapter 110 / `One-Sided Fixed-Sample Tests in Clinical Trials` (PDF pp. 8963–8965); S154 / Chapter 110 / `Two-Sided Fixed-Sample Tests in Clinical Trials` (PDF pp. 8965–8968); S154 / Chapter 110 / `Group Sequential Methods` (PDF pp. 8968–8971).
 * Discriminates: Example 110.8: Creating a One-Sided Error Spending Design
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
proc seqdesign altref=0.2 errspend
pss(cref=0 0.5 1)
stopprob(cref=0 0.5 1)
plots=(asn power errspend)
;
OneSidedErrorSpending: design nstages=5
method(alpha)=errfuncobf
method(beta)=errfuncpoc
alt=upper stop=both
alpha=0.025
;
run;
