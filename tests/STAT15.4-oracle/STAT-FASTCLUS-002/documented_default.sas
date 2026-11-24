/* STAT-FASTCLUS-002: FASTCLUS — Fast clustering initialization, iteration, and assignment
 * Source: S154 / Chapter 45 / `Getting Started: FASTCLUS Procedure` (PDF pp. 2896–2903); S154 / Chapter 45 / `Overview: FASTCLUS Procedure` (PDF pp. 2894–2896).
 * Discriminates: Small synthetic/public-input default model adapted to the documented Getting Started procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc fastclus data=sashelp.iris maxclusters=3 maxiter=50 out=clusters; var SepalLength SepalWidth PetalLength PetalWidth; run;
proc freq data=clusters; tables Species*Cluster; run;
