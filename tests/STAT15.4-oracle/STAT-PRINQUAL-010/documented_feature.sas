/* STAT-PRINQUAL-010: PRINQUAL — Computational Resources
 * Source: S154 / Chapter 99 / `Computational Resources` (PDF pp. 8070–8071).
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

proc prinqual data=sashelp.class out=scaled;
transform identity(height weight age);
run;
proc print data=scaled(obs=5) noobs;
run;
