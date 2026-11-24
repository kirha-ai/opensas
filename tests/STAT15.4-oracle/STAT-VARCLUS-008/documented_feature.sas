/* STAT-VARCLUS-008: VARCLUS — Computational Resources
 * Source: S154 / Chapter 129 / `Computational Resources` (PDF pp. 10712–10713).
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

proc varclus data=sashelp.iris maxclusters=2 outstat=structure;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
proc print data=structure(obs=15) noobs;
run;
