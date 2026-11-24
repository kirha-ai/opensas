/* STAT-VARCLUS-002: VARCLUS — Variable clustering and component representation
 * Source: S154 / Chapter 129 / `Getting Started: VARCLUS Procedure` (PDF pp. 10696–10699); S154 / Chapter 129 / `Overview: VARCLUS Procedure` (PDF pp. 10694–10696).
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

proc varclus data=sashelp.iris maxclusters=2 outstat=structure; var SepalLength SepalWidth PetalLength PetalWidth; run;
proc print data=structure(obs=15) noobs; run;
