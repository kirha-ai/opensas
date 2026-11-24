/* STAT-FASTCLUS-006: FASTCLUS — Computational Resources
 * Source: S154 / Chapter 45 / `Computational Resources` (PDF pp. 2917–2918).
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

proc fastclus data=sashelp.iris maxclusters=3 maxiter=50 out=clusters;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
proc freq data=clusters;
tables Species*Cluster;
run;
