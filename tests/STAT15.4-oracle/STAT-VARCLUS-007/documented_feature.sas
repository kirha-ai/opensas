/* STAT-VARCLUS-007: VARCLUS — ODS Graphics
 * Source: S154 / Chapter 129 / `ODS Graphics` (PDF pp. 10715–10716).
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
ods trace on;
ods trace on;
proc varclus data=sashelp.iris maxclusters=2 outstat=structure;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
proc print data=structure(obs=15) noobs;
run;
ods trace off;
ods trace off;
ods graphics off;
