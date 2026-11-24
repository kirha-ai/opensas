/* STAT-BOXPLOT-002: BOXPLOT — Grouped box plot summary statistics and default graph data
 * Source: S154 / Chapter 32 / `Getting Started: BOXPLOT Procedure` (PDF pp. 1368–1376); S154 / Chapter 32 / `Overview: BOXPLOT Procedure` (PDF pp. 1366–1368).
 * Discriminates: Grouped box plot request and the corresponding explicit distribution summaries
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

filename _grfile temp; goptions device=svg gsfname=_grfile;
proc sort data=sashelp.cars out=cars; by Origin; run;
ods graphics on;
proc boxplot data=cars; plot MPG_City*Origin; run;
ods graphics off;
proc means data=cars n mean std min q1 median q3 max; class Origin; var MPG_City; run;
