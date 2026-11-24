/* STAT-PRINQUAL-002: PRINQUAL — Optimal scaling transformations and principal component analysis
 * Source: S154 / Chapter 99 / `Getting Started: PRINQUAL Procedure` (PDF pp. 8035–8040); S154 / Chapter 99 / `Overview: PRINQUAL Procedure` (PDF pp. 8034–8035).
 * Discriminates: Documented default analysis with explicit complete public or synthetic inputs
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc prinqual data=sashelp.class out=scaled; transform identity(height weight age); run;
proc print data=scaled(obs=5) noobs; run;
