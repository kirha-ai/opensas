/* STAT-STEPDISC-003: STEPDISC — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 117 / `Displayed Output` (PDF pp. 9567–9569); S154 / Chapter 117 / `ODS Table Names` (PDF pp. 9569–9570).
 * Discriminates: Getting Started: STEPDISC Procedure
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
title 'Fish Measurement Data';
proc stepdisc data=sashelp.fish;
class Species;
run;
ods trace off;
