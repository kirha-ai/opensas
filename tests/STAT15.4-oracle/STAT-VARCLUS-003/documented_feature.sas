/* STAT-VARCLUS-003: VARCLUS — PARTIAL / SEED / Using the VARCLUS procedure
 * Source: S154 / Chapter 129 / `PARTIAL Statement` (PDF p. 10708); S154 / Chapter 129 / `SEED Statement` (PDF p. 10708); S154 / Chapter 129 / `Using the VARCLUS procedure` (PDF pp. 10709–10710).
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
