/* STAT-SPP-009: SPP — COVTEST / Testing for Complete Spatial Randomness / Confidence Intervals for Summary Statistics
 * Source: S154 / Chapter 114 / `COVTEST Statement` (PDF pp. 9398–9399); S154 / Chapter 114 / `Testing for Complete Spatial Randomness` (PDF p. 9410); S154 / Chapter 114 / `Confidence Intervals for Summary Statistics` (PDF p. 9416).
 * Discriminates: Example 114.2: Testing Covariate Dependence of a Point Pattern; explicit statements: COVTEST
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc spp data=sashelp.bei;
process trees = (x,y /area=(0,0,1000,500) event=Trees);
trend grad = field(x,y,Gradient);
trend elev = field(x,y,Elevation);
covtest trees = grad elev;
run;
