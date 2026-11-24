/* STAT-STEPDISC-001: STEPDISC — Data input, variable roles, and basic options
 * Source: S154 / Chapter 117 / `PROC STEPDISC Statement` (PDF pp. 9559–9563); S154 / Chapter 117 / `BY Statement` (PDF pp. 9563–9564); S154 / Chapter 117 / `CLASS Statement` (PDF p. 9564); S154 / Chapter 117 / `FREQ Statement` (PDF p. 9564); S154 / Chapter 117 / `VAR Statement` (PDF p. 9564); S154 / Chapter 117 / `WEIGHT Statement` (PDF pp. 9564–9565); S154 / Chapter 117 / `Missing Values` (PDF p. 9565); S154 / Chapter 117 / `Input Data Sets` (PDF pp. 9565–9566).
 * Discriminates: Verified default procedure context; explicit statements: CLASS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Fish Measurement Data';
proc stepdisc data=sashelp.fish;
class Species;
run;
