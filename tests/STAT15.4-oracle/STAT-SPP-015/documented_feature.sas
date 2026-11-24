/* STAT-SPP-015: SPP — Official examples and feature integration regression
 * Source: S154 / Chapter 114 / `Examples: SPP Procedure` (PDF pp. 9431–9444).
 * Discriminates: Example 114.2: Testing Covariate Dependence of a Point Pattern
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
