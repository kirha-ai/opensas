/* STAT-ADAPTIVEREG-005: ADAPTIVEREG — PARTITION
 * Source: S154 / Chapter 28 / `PARTITION Statement` (PDF pp. 1072–1073).
 * Discriminates: Example 28.3: Predicting E-Mail Spam; explicit statements: PARTITION
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);
data mixture; call streaminit(731); do i=1 to 120; x1=rand('uniform'); c1=mod(i,3); y=2*c1+4*x1+2*max(x1-0.5,0)+rand('normal')*0.2; output; end; run;
proc adaptivereg data=mixture details=(bases fwdsummary bwdsummary); class c1; model y=c1 x1; output out=predicted; run;
proc print data=predicted(obs=10) noobs; run;
