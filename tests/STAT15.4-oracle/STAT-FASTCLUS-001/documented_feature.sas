/* STAT-FASTCLUS-001: FASTCLUS — Data input, variable roles, and basic options
 * Source: S154 / Chapter 45 / `PROC FASTCLUS Statement` (PDF pp. 2903–2910); S154 / Chapter 45 / `BY Statement` (PDF pp. 2910–2911); S154 / Chapter 45 / `FREQ Statement` (PDF pp. 2911–2912); S154 / Chapter 45 / `ID Statement` (PDF p. 2912); S154 / Chapter 45 / `VAR Statement` (PDF p. 2912); S154 / Chapter 45 / `WEIGHT Statement` (PDF p. 2912); S154 / Chapter 45 / `Missing Values` (PDF p. 2913).
 * Discriminates: Verified default procedure context; explicit statements: FREQ, VAR
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
