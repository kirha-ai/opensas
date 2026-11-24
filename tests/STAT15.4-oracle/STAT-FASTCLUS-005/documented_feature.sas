/* STAT-FASTCLUS-005: FASTCLUS — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 45 / `Displayed Output` (PDF pp. 2920–2922); S154 / Chapter 45 / `ODS Table Names` (PDF pp. 2922–2923).
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

ods trace on;
proc fastclus data=sashelp.iris maxclusters=3 maxiter=50 out=clusters;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
proc freq data=clusters;
tables Species*Cluster;
run;
ods trace off;
