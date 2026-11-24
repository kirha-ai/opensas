/* STAT-TREE-002: TREE — Hierarchical tree input, cutting, and cluster membership
 * Source: S154 / Chapter 127 / `Getting Started: TREE Procedure` (PDF pp. 10570–10575); S154 / Chapter 127 / `Overview: TREE Procedure` (PDF p. 10570).
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

proc cluster data=sashelp.iris method=ward outtree=tree noprint; var SepalLength SepalWidth PetalLength PetalWidth; run;
proc tree data=tree nclusters=3 out=members noprint; run;
proc print data=members(obs=12) noobs; run;
