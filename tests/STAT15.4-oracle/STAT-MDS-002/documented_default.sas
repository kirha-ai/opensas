/* STAT-MDS-002: MDS — Default multidimensional scaling fit
 * Source: S154 / Chapter 81 / `Getting Started: MDS Procedure` (PDF pp. 6379–6382); S154 / Chapter 81 / `Overview: MDS Procedure` (PDF pp. 6378–6379).
 * Discriminates: Getting Started: MDS Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Analysis of Flying Mileages between Ten U.S. Cities';
ods graphics on;
proc mds data=sashelp.mileages level=absolute;
id city;
run;
